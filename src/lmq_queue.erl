-module(lmq_queue).
-behaviour(gen_server).
-export([start_link/1, start_link/2, stop/1,
    push/2, pull/1, done/2, retain/2, release/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-include("lmq.hrl").
-record(state, {name, timeout, waiting=queue:new(), monitors=gb_sets:empty()}).

start_link(Name) when is_atom(Name) ->
    start_link(Name, ?DEFAULT_TIMEOUT).

start_link(Name, Timeout) when is_atom(Name), Timeout >= 0 ->
    gen_server:start_link(?MODULE, [Name, Timeout], []).

push(Pid, Data) ->
    gen_server:call(Pid, {push, Data}).

pull(Pid) ->
    gen_server:call(Pid, pull, infinity).

done(Pid, UUID) ->
    gen_server:call(Pid, {done, UUID}).

retain(Pid, UUID) ->
    gen_server:call(Pid, {retain, UUID}).

release(Pid, UUID) ->
    gen_server:call(Pid, {release, UUID}).

stop(Pid) ->
    gen_server:call(Pid, stop).

init([Name, Timeout]) ->
    ok = lmq_lib:create(Name),
    lmq_queue_mgr:queue_started(Name, self()),
    {ok, #state{name=Name, timeout=Timeout}}.

handle_call({push, Data}, _From, S=#state{name=Name}) ->
    R = lmq_lib:enqueue(Name, Data),
    case queue:is_empty(S#state.waiting) of
        true  -> {reply, R, S};
        false -> {reply, R, S, lmq_lib:waittime(Name)}
    end;
handle_call(pull, From={Pid, _}, S=#state{}) ->
    Ref = erlang:monitor(process, Pid),
    Waiting = queue:in({From, Ref}, S#state.waiting),
    Monitors = gb_sets:add(Ref, S#state.monitors),
    {noreply, S#state{waiting=Waiting, monitors=Monitors}, lmq_lib:waittime(S#state.name)};
handle_call({done, UUID}, _From, S=#state{}) ->
    {reply, lmq_lib:done(S#state.name, UUID), S};
handle_call({retain, UUID}, _From, S=#state{}) ->
    {reply, lmq_lib:retain(S#state.name, UUID), S};
handle_call({release, UUID}, _From, S=#state{}) ->
    {reply, lmq_lib:release(S#state.name, UUID), S};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, S=#state{}) ->
    NewState = maybe_push_message(S),
    case queue:is_empty(NewState#state.waiting) of
        true  -> {noreply, NewState};
        false -> {noreply, NewState, lmq_lib:waittime(S#state.name)}
    end;
handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{monitors=M}) ->
    case gb_sets:is_member(Ref, M) of
        true ->
            erlang:demonitor(Ref, [flush]),
            Waiting = queue:filter(
                fun({_, V}) when V =:= Ref -> false;
                   (_) -> true
                end, S#state.waiting),
            {noreply, S#state{waiting=Waiting, monitors=gb_sets:delete(Ref, M)}};
        false ->
            {noreply, S}
    end;
handle_info(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

maybe_push_message(S=#state{waiting=Waiting}) ->
    case queue:is_empty(Waiting) of
        true -> S;
        false ->
            case lmq_lib:dequeue(S#state.name) of
                empty -> S;
                Msg ->
                    case queue:out(Waiting) of
                        {{value, {From, Ref}}, NewWaiting} ->
                            erlang:demonitor(Ref, [flush]),
                            Monitors = gb_sets:delete(Ref, S#state.monitors),
                            gen_server:reply(From, Msg),
                            S#state{waiting=NewWaiting, monitors=Monitors};
                        {empty, Waiting} ->
                            S
                    end
            end
    end.
