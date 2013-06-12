-module(lmq_queue).
-behaviour(gen_server).
-export([start_link/0, push/1, pull/0, complete/1, alive/1, return/1, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

-include("lmq.hrl").
-record(state, {waiting=queue:new(), monitors=gb_sets:empty()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

push(Data) ->
    gen_server:call(?MODULE, {push, Data}).

pull() ->
    gen_server:call(?MODULE, pull, infinity).

complete(UUID) ->
    gen_server:call(?MODULE, {complete, UUID}).

alive(UUID) ->
    gen_server:call(?MODULE, {alive, UUID}).

return(UUID) ->
    gen_server:call(?MODULE, {return, UUID}).

stop() ->
    gen_server:call(?MODULE, stop).

init([]) ->
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call({push, Data}, _From, S=#state{}) ->
    R = lmq_lib:enqueue(Data),
    case queue:is_empty(S#state.waiting) of
        true  -> {reply, R, S};
        false -> {reply, R, S, lmq_lib:waittime()}
    end;
handle_call(pull, From={Pid, _}, S=#state{}) ->
    Ref = erlang:monitor(process, Pid),
    Waiting = queue:in({From, Ref}, S#state.waiting),
    Monitors = gb_sets:add(Ref, S#state.monitors),
    {noreply, S#state{waiting=Waiting, monitors=Monitors}, lmq_lib:waittime()};
handle_call({complete, UUID}, _From, State) ->
    {reply, lmq_lib:complete(UUID), State};
handle_call({alive, UUID}, _From, State) ->
    {reply, lmq_lib:reset_timeout(UUID), State};
handle_call({return, UUID}, _From, State) ->
    {reply, lmq_lib:return(UUID), State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(Msg, State) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, S=#state{}) ->
    NewState = maybe_push_message(S),
    case queue:is_empty(NewState#state.waiting) of
        true  -> {noreply, NewState};
        false -> {noreply, NewState, lmq_lib:waittime()}
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
            case lmq_lib:dequeue() of
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
