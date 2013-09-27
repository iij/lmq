-module(lmq_queue_mgr).

-behaviour(gen_server).
-export([start_link/0, queue_started/2, delete/1, get/1, get/2, match/1,
    set_default_props/1, get_default_props/0]).
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

get(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {get, Name, []}).

get(Name, Opts) when is_atom(Name) ->
    gen_server:call(?MODULE, {get, Name, Opts}).

match(Regexp) when is_list(Regexp); is_binary(Regexp) ->
    gen_server:call(?MODULE, {match, Regexp}).

delete(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {delete, Name}).

set_default_props(PropsList) ->
    gen_server:call(?MODULE, {set_default_props, PropsList}).

get_default_props() ->
    gen_server:call(?MODULE, {get_default_props}).

%% ==================================================================
%% gen_server callbacks
%% ==================================================================

init([]) ->
    lager:info("Starting the queue manager: ~p", [self()]),
    lists:foreach(fun(Name) ->
        lmq_queue:start(Name)
    end, lmq_lib:all_queue_names()),
    {ok, #state{}}.

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

handle_call({get, Name, Opts}, _From, S=#state{}) when is_atom(Name) ->
    case dict:find(Name, S#state.qmap) of
        {ok, {Pid, _}} ->
            case proplists:get_value(update, Opts) of
                true ->
                    Base = lmq_lib:queue_info(Name),
                    Props = proplists:get_value(props, Opts, []),
                    Props1 = lmq_misc:extend(Props, Base),
                    ok = lmq_queue:props(Pid, Props1),
                    lager:info("Queue properties are updated: ~s ~p", [Name, Props]),
                    {reply, Pid, S};
                undefined ->
                    {reply, Pid, S}
            end;
        error ->
            case proplists:get_value(create, Opts) of
                true ->
                    {ok, Pid} = case proplists:get_value(props, Opts) of
                        undefined -> lmq_queue:start(Name);
                        Props -> lmq_queue:start(Name, Props)
                    end,
                    lager:info("The new queue created: ~s ~p", [Name, Pid]),
                    {reply, Pid, update_qmap(Name, Pid, S)};
                undefined ->
                    {reply, not_found, S}
            end
    end;

handle_call({match, Regexp}, _From, S=#state{}) ->
    R = case re:compile(Regexp) of
        {ok, MP} ->
            dict:fold(fun(Name, {Pid, _}, Acc) ->
                case re:run(atom_to_list(Name), MP) of
                    {match, _} -> [{Name, Pid} | Acc];
                    _ -> Acc
                end
            end, [], S#state.qmap);
        {error, _} ->
            {error, invalid_regexp}
    end,
    {reply, R, S};

handle_call({set_default_props, PropsList}, _From, S=#state{}) ->
    case validate_props_list(PropsList) of
        {ok, _PropsList} ->
            lmq_lib:set_lmq_info(default_props, PropsList),
            dict:fold(fun(_, {Pid, _}, _) ->
                lmq_queue:reload_properties(Pid)
            end, ok, S#state.qmap),
            {reply, ok, S};
        {error, Reason} ->
            {reply, Reason, S}
    end;

handle_call({get_default_props}, _From, S=#state{}) ->
    PropsList = case lmq_lib:get_lmq_info(default_props) of
        {ok, Value} -> Value;
        _ -> []
    end,
    {reply, PropsList, S};

handle_call(Msg, _From, State) ->
    lager:warning("Unknown message: ~p", [Msg]),
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
    lager:warning("Unknown message: ~p", [Msg]),
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

validate_props_list(PropsList) ->
    try
        {ok, validate_props_list(PropsList, [])}
    catch
        error:function_clause -> {error, invalid_syntax}
    end.

validate_props_list([], Acc) ->
    lists:reverse(Acc);

validate_props_list([{Regexp, Props}|T], Acc) when is_list(Regexp); is_binary(Regexp), is_list(Props) ->
    {ok, MP} = re:compile(Regexp),
    Props1 = lmq_misc:extend(Props, ?DEFAULT_QUEUE_PROPS),
    validate_props_list(T, [{MP, Props1} | Acc]).

%% ==================================================================
%% EUnit tests
%% ==================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

validate_props_test() ->
    ?assertEqual(
        {ok, [{element(2, re:compile("lmq/a")), [{pack, 0}, {retry, 1}, {timeout, 30}]},
              {element(2, re:compile("lmq/.*")), [{pack, 0}, {retry, 2}, {timeout, 60}]}]},
        validate_props_list([{"lmq/a", [{retry, 1}]},
                             {"lmq/.*", [{timeout, 60}]}])),
    ?assertEqual(
        {ok, [{element(2, re:compile(<<"lmq/.*">>)), [{pack, 0}, {retry, 1}, {timeout, 30}]}]},
        validate_props_list([{<<"lmq/.*">>, [{retry, 1}]}])),
    ?assertEqual(
        {error, invalid_syntax},
        validate_props_list([{"lmq/a", {retry, 1}}])).

-endif.
