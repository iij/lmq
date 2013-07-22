-module(lmq_queue).
-behaviour(gen_server).
-export([start/1, start_link/1, start_link/2, stop/1,
    push/2, pull/1, pull/2, pull_async/1, pull_async/2, pull_cancel/2,
    done/2, retain/2, release/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-include("lmq.hrl").
-record(state, {name, props, waiting=queue:new(), monitors=gb_sets:empty()}).
-record(waiting, {from, ref, timeout, start_time=lmq_misc:unixtime()}).

start(Name) ->
    supervisor:start_child(lmq_queue_sup, [Name]).

start_link(Name) when is_atom(Name) ->
    case lmq_lib:queue_info(Name) of
        not_found ->
            start_link(Name, ?DEFAULT_QUEUE_PROPS);
        _ ->
            gen_server:start_link(?MODULE, Name, [])
    end.

start_link(Name, Props) when is_atom(Name) ->
    ok = lmq_lib:create(Name, Props),
    gen_server:start_link(?MODULE, Name, []).

push(Pid, Data) ->
    gen_server:call(Pid, {push, Data}).

pull(Pid) ->
    gen_server:call(Pid, {pull, infinity}, infinity).

pull(Pid, 0) ->
    %% in this case, cannot use gen_server's timeout
    case gen_server:call(Pid, {pull, 0}) of
        {error, timeout} -> empty;
        R -> R
    end;

pull(Pid, Timeout) ->
    try gen_server:call(Pid, {pull, Timeout}, round(Timeout * 1000)) of
        R -> R
    catch
        exit:{timeout, _} -> empty
    end.

pull_async(Pid) ->
    pull_async(Pid, infinity).

pull_async(Pid, Timeout) ->
    gen_server:call(Pid, {pull_async, Timeout}).

pull_cancel(Pid, Ref) ->
    gen_server:call(Pid, {pull_cancel, Ref}).

done(Pid, UUID) ->
    gen_server:call(Pid, {done, UUID}).

retain(Pid, UUID) ->
    gen_server:call(Pid, {retain, UUID}).

release(Pid, UUID) ->
    gen_server:call(Pid, {release, UUID}).

stop(Pid) ->
    gen_server:call(Pid, stop).

init(Name) ->
    Props = lmq_lib:queue_info(Name),
    lmq_queue_mgr:queue_started(Name, self()),
    {ok, #state{name=Name, props=Props}}.

handle_call({push, Data}, _From, S=#state{}) ->
    Retry = proplists:get_value(retry, S#state.props),
    Opts = case proplists:get_value(pack, S#state.props) of
        T when is_integer(T) -> [{retry, Retry}, {pack, T}];
        _ -> [{retry, Retry}]
    end,
    R = lmq_lib:enqueue(S#state.name, Data, Opts),
    {State, Sleep} = prepare_sleep(S),
    {reply, R, State, Sleep};

handle_call({pull, Timeout}, From={Pid, _}, S=#state{}) ->
    State = add_waiting(From, Pid, Timeout, S),
    {State1, Sleep} = prepare_sleep(State),
    {noreply, State1, Sleep};

handle_call({pull_async, Timeout}, {Pid, _}, S=#state{}) ->
    State = add_waiting(Pid, Timeout, S),
    Ref = (queue:get_r(State#state.waiting))#waiting.ref,
    {State1, Sleep} = prepare_sleep(State),
    {reply, Ref, State1, Sleep};

handle_call({pull_cancel, Ref}, _From, S=#state{}) ->
    State = remove_waiting(Ref, S),
    {State1, Sleep} = prepare_sleep(State),
    {reply, ok, State1, Sleep};

handle_call({done, UUID}, _From, S=#state{}) ->
    R = lmq_lib:done(S#state.name, UUID),
    {State, Sleep} = prepare_sleep(S),
    {reply, R, State, Sleep};

handle_call({retain, UUID}, _From, S=#state{props=Props}) ->
    R = lmq_lib:retain(S#state.name, UUID, proplists:get_value(timeout, Props)),
    {State, Sleep} = prepare_sleep(S),
    {reply, R, State, Sleep};

handle_call({release, UUID}, _From, S=#state{}) ->
    R = lmq_lib:release(S#state.name, UUID),
    {State, Sleep} = prepare_sleep(S),
    {reply, R, State, Sleep};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, S=#state{}) ->
    NewState = maybe_push_message(S),
    lager:debug("number of waitings: ~p", [queue:len(NewState#state.waiting)]),
    {State, Sleep} = prepare_sleep(NewState),
    {noreply, State, Sleep};

handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{}) ->
    State = remove_waiting(Ref, S),
    {State1, Sleep} = prepare_sleep(State),
    {noreply, State1, Sleep};

handle_info(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

maybe_push_message(S=#state{props=Props, waiting=Waiting}) ->
    case queue:out(Waiting) of
        {{value, W=#waiting{ref=Ref}}, NewWaiting} ->
            Timeout = proplists:get_value(timeout, Props),
            %% timeout = 0 is special case and it is safe to use it,
            %% because invalid waitings are removed before sleeping.
            %% thus, only waitings added in this tick are remained.
            case (W#waiting.timeout =:= 0 orelse wait_valid(W)) andalso
                    lmq_lib:dequeue(S#state.name, Timeout) of
                false -> %% client timeout
                    maybe_push_message(S#state{waiting=NewWaiting});
                empty ->
                    S;
                Msg ->
                    erlang:demonitor(Ref, [flush]),
                    Monitors = gb_sets:delete(Ref, S#state.monitors),
                    case W#waiting.from of
                        {_, _}=From -> gen_server:reply(From, Msg);
                        P when is_pid(P) -> P ! {Ref, Msg}
                    end,
                    S#state{waiting=NewWaiting, monitors=Monitors}
            end;
        {empty, Waiting} ->
            S
    end.

add_waiting(Pid, Timeout, S=#state{}) ->
    add_waiting(Pid, Pid, Timeout, S).

add_waiting(From, MonitorPid, Timeout, S=#state{}) ->
    Ref = erlang:monitor(process, MonitorPid),
    Waiting = queue:in(#waiting{from=From, ref=Ref, timeout=Timeout},
                       S#state.waiting),
    Monitors = gb_sets:add(Ref, S#state.monitors),
    S#state{waiting=Waiting, monitors=Monitors}.

remove_waiting(Ref, S=#state{monitors=M}) ->
    case gb_sets:is_member(Ref, M) of
        true ->
            erlang:demonitor(Ref, [flush]),
            Waiting = queue:filter(
                fun(#waiting{ref=V}) when V =:= Ref -> false;
                   (_) -> true
                end, S#state.waiting),
            S#state{waiting=Waiting, monitors=gb_sets:delete(Ref, M)};
        false ->
            S
    end.

wait_valid(#waiting{timeout=infinity}) ->
    true;
wait_valid(#waiting{start_time=StartTime, timeout=Timeout}) ->
    StartTime + Timeout > lmq_misc:unixtime().

prepare_sleep(S=#state{}) ->
    case queue:is_empty(S#state.waiting) of
        true  -> {S, infinity};
        false ->
            case lmq_lib:waittime(S#state.name) of
                0 -> {S, 0};
                T ->
                    %% remove invalid waitings before sleeping
                    F = fun(W=#waiting{}) ->
                        case wait_valid(W) of
                            true -> true;
                            false ->
                                case W#waiting.from of
                                    {_, _}=From -> gen_server:reply(From, {error, timeout});
                                    P when is_pid(P) -> P ! {W#waiting.ref, {error, timeout}}
                                end,
                                false
                        end
                    end,
                    {S#state{waiting=queue:filter(F, S#state.waiting)}, T}
            end
    end.
