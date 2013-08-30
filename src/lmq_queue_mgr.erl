-module(lmq_queue_mgr).

-behaviour(gen_server).
-export([start_link/0, queue_started/2, create/1, create/2, delete/1,
    find/1, find/2, match/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-include("lmq.hrl").

-record(state, {sup, qmap=dict:new()}).

%% ==================================================================
%% Public API
%% ==================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

queue_started(Name, QPid) when is_atom(Name) ->
    gen_server:cast(?MODULE, {queue_started, Name, QPid}).

create(Name) when is_atom(Name) ->
    create(Name, ?DEFAULT_QUEUE_PROPS).

create(Name, Props) when is_atom(Name) ->
    gen_server:call(?MODULE, {create, Name, Props}).

find(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {find, Name, []}).

find(Name, Opts) when is_atom(Name) ->
    gen_server:call(?MODULE, {find, Name, Opts}).

match(Regexp) when is_list(Regexp); is_binary(Regexp) ->
    gen_server:call(?MODULE, {match, Regexp}).

delete(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {delete, Name}).

%% ==================================================================
%% gen_server callbacks
%% ==================================================================

init([]) ->
    lists:foreach(fun(Name) ->
        lmq_queue:start(Name)
    end, lmq_lib:all_queue_names()),
    {ok, #state{}}.

handle_call({create, Name, Props}, _From, S=#state{qmap=QMap}) when is_atom(Name) ->
    case dict:is_key(Name, QMap) of
        true ->
            {reply, ok, S};
        false ->
            ok = lmq_lib:create(Name, Props),
            NewQMap = dict:store(Name, undefined, S#state.qmap),
            {ok, _} = lmq_queue:start(Name),
            {reply, ok, S#state{qmap=NewQMap}}
    end;
handle_call({delete, Name}, _From, S=#state{}) when is_atom(Name) ->
    State = case dict:find(Name, S#state.qmap) of
        {ok, {Pid, _}} ->
            lmq_queue:stop(Pid),
            S#state{qmap=dict:erase(Name, S#state.qmap)};
        error ->
            S
    end,
    ok = lmq_lib:delete(Name),
    {reply, ok, State};

handle_call({find, Name, Opts}, _From, S=#state{}) when is_atom(Name) ->
    case dict:find(Name, S#state.qmap) of
        {ok, {Pid, _}} ->
            case proplists:get_value(update, Opts) of
                true ->
                    Props = proplists:get_value(props, Opts, ?DEFAULT_QUEUE_PROPS),
                    ok = lmq_queue:props(Pid, Props),
                    {reply, Pid, S};
                undefined ->
                    {reply, Pid, S}
            end;
        error ->
            case proplists:get_value(create, Opts) of
                true ->
                    Props = proplists:get_value(props, Opts, ?DEFAULT_QUEUE_PROPS),
                    ok = lmq_lib:create(Name, Props),
                    {ok, Pid} = lmq_queue:start(Name),
                    lager:info("A queue named ~s is created"),
                    {reply, Pid, update_qmap(Name, Pid, S)};
                undefined ->
                    {reply, not_found, S}
            end
    end;

handle_call({match, Regexp}, _From, S=#state{}) ->
    R = case re:compile(Regexp) of
        {ok, MP} ->
            dict:fold(fun(Key, {Pid, _}, Acc) ->
                case re:run(atom_to_list(Key), MP) of
                    {match, _} -> [Pid | Acc];
                    _ -> Acc
                end
            end, [], S#state.qmap);
        {error, _} ->
            {error, invalid_regexp}
    end,
    {reply, R, S};
handle_call(Msg, _From, State) ->
    io:format("Unknown message: ~p~n", [Msg]),
    {noreply, State}.

handle_cast({queue_started, Name, Pid}, S) when is_atom(Name) ->
    {noreply, update_qmap(Name, Pid, S)};

handle_cast(_, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{qmap=QMap}) ->
    NewQMap = dict:filter(fun(_, {_, R}) ->
        R =/= Ref
    end, QMap),
    {noreply, S#state{qmap=NewQMap}};
handle_info(Msg, State) ->
    io:format("Unknown message: ~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ==================================================================
%% Private functions
%% ==================================================================

update_qmap(Name, Pid, #state{qmap=QMap}=S) ->
    Ref = erlang:monitor(process, Pid),
    S#state{qmap=dict:store(Name, {Pid, Ref}, QMap)}.
