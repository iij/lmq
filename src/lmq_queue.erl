-module(lmq_queue).
-behaviour(gen_server).
-export([start/1, start_link/1, start_link/2, stop/1,
    push/2, pull/1, pull/2, done/2, retain/2, release/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-include("lmq.hrl").
-record(state, {name, props, waiting=queue:new(), monitors=gb_sets:empty()}).

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

pull(Pid, Timeout) ->
    try gen_server:call(Pid, {pull, Timeout}, round(Timeout * 1000)) of
        R -> R
    catch
        exit:{timeout, _} -> empty
    end.

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
    R = lmq_lib:enqueue(S#state.name, Data),
    {reply, R, S, get_timeout(S)};
handle_call({pull, Timeout}, From={Pid, _}, S=#state{}) ->
    ExpireAt = case Timeout of
        infinity -> infinity;
        _ -> lmq_misc:unixtime() + Timeout
    end,
    Ref = erlang:monitor(process, Pid),
    Waiting = queue:in({From, ExpireAt, Ref}, S#state.waiting),
    Monitors = gb_sets:add(Ref, S#state.monitors),
    NewState = S#state{waiting=Waiting, monitors=Monitors},
    {noreply, NewState, get_timeout(NewState)};
handle_call({done, UUID}, _From, S=#state{}) ->
    {reply, lmq_lib:done(S#state.name, UUID), S, get_timeout(S)};
handle_call({retain, UUID}, _From, S=#state{props=Props}) ->
    R = lmq_lib:retain(S#state.name, UUID, proplists:get_value(timeout, Props)),
    {reply, R, S, get_timeout(S)};
handle_call({release, UUID}, _From, S=#state{}) ->
    {reply, lmq_lib:release(S#state.name, UUID), S, get_timeout(S)};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, S=#state{}) ->
    NewState = maybe_push_message(S),
    lager:debug("number of waitings: ~p", [queue:len(NewState#state.waiting)]),
    {noreply, NewState, get_timeout(NewState)};
handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{monitors=M}) ->
    NewState = case gb_sets:is_member(Ref, M) of
        true ->
            erlang:demonitor(Ref, [flush]),
            Waiting = queue:filter(
                fun({_, _, V}) when V =:= Ref -> false;
                   (_) -> true
                end, S#state.waiting),
            S#state{waiting=Waiting, monitors=gb_sets:delete(Ref, M)};
        false ->
            S
    end,
    {noreply, NewState, get_timeout(NewState)};
handle_info(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

maybe_push_message(S=#state{props=Props, waiting=Waiting}) ->
    case queue:out(Waiting) of
        {{value, {From, ExpireAt, Ref}}, NewWaiting} ->
            Timeout = proplists:get_value(timeout, Props),
            case ExpireAt > lmq_misc:unixtime() andalso
                    lmq_lib:dequeue(S#state.name, Timeout) of
                false -> %% client timeout
                    maybe_push_message(S#state{waiting=NewWaiting});
                empty ->
                    S;
                Msg ->
                    erlang:demonitor(Ref, [flush]),
                    Monitors = gb_sets:delete(Ref, S#state.monitors),
                    gen_server:reply(From, Msg),
                    S#state{waiting=NewWaiting, monitors=Monitors}
            end;
        {empty, Waiting} ->
            S
    end.

get_timeout(S=#state{}) ->
    case queue:is_empty(S#state.waiting) of
        true  -> infinity;
        false -> lmq_lib:waittime(S#state.name)
    end.
