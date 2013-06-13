-module(lmq_queue_mgr).

-behaviour(gen_server).
-export([start_link/1, create/1, find/1, match/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-define(SPEC, {lmq_queue_sup,
               {lmq_queue_sup, start_link, []},
               permanent, 10000,
               supervisor, [lmq_queue_sup]}).

-record(state, {sup, qmap=dict:new()}).

start_link(Sup) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Sup], []).

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

handle_call({create, Name}, _From, S=#state{qmap=M}) when is_atom(Name) ->
    ok = lmq_lib:create(Name),
    Value = start_queue(S#state.sup, Name),
    {reply, ok, S#state{qmap=dict:store(Name, Value, M)}};
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

handle_cast(_, State) ->
    {noreply, State}.

handle_info({start_queue_supervisor, Sup}, S=#state{}) ->
    {ok, Pid} = supervisor:start_child(Sup, ?SPEC),
    {noreply, S#state{sup=Pid}};
handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{qmap=QMap}) ->
    [Name] = dict:fold(fun(Key, {_, R}, Acc) ->
        case R =:= Ref of
            true -> [Key];
            false -> Acc
        end
    end, [], QMap),
    Value = start_queue(S#state.sup, Name),
    {noreply, S#state{qmap=dict:store(Name, Value, QMap)}};
handle_info(Msg, State) ->
    io:format("Unknown message: ~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

start_queue(Sup, Name) ->
    {ok, Pid} = supervisor:start_child(Sup, [Name]),
    Ref = erlang:monitor(process, Pid),
    {Pid, Ref}.
