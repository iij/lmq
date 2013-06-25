-module(lmq_queue_mgr).

-behaviour(gen_server).
-export([start_link/1, queue_started/2, create/1, find/1, match/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-define(SPEC, {lmq_queue_sup,
               {lmq_queue_sup, start_link, []},
               permanent, 10000,
               supervisor, [lmq_queue_sup]}).

-record(state, {sup, qmap=dict:new()}).

start_link(Sup) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Sup], []).

queue_started(Name, QPid) when is_atom(Name) ->
    gen_server:cast(?MODULE, {queue_started, Name, QPid}).

create(Name) when is_list(Name) ->
    create(list_to_atom(Name));
create(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {create, Name}).

find(Name) when is_list(Name) ->
    find(list_to_atom(Name));
find(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {find, Name}).

match(Regexp) when is_list(Regexp) ->
    gen_server:call(?MODULE, {match, Regexp}).

init([Sup]) ->
    %% start queue supervisor later in order to avoid deadlock
    self() ! {start_queue_supervisor, Sup},
    {ok, #state{}}.

handle_call({create, Name}, _From, S=#state{}) when is_atom(Name) ->
    ok = lmq_lib:create(Name),
    {ok, _} = supervisor:start_child(S#state.sup, [Name]),
    {reply, ok, S};
handle_call({find, Name}, _From, S=#state{}) when is_atom(Name) ->
    R = case dict:find(Name, S#state.qmap) of
        {ok, {Pid, _}} -> Pid;
        error -> not_found
    end,
    {reply, R, S};
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

handle_cast({queue_started, Name, QPid}, S=#state{qmap=QMap}) when is_atom(Name) ->
    Ref = erlang:monitor(process, QPid),
    {noreply, S#state{qmap=dict:store(Name, {QPid, Ref}, QMap)}};
handle_cast(_, State) ->
    {noreply, State}.

handle_info({start_queue_supervisor, Sup}, S=#state{}) ->
    {ok, Pid} = supervisor:start_child(Sup, ?SPEC),
    {noreply, S#state{sup=Pid}};
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
