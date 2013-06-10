-module(lmq_queue_server).
-behaviour(gen_server).
-compile(export_all).

-record(state, {refs=gb_sets:empty(), queue=queue:new()}).

start() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE, stop).

push(Data) ->
    gen_server:call(?MODULE, {push, Data}).

pull() ->
    gen_server:call(?MODULE, pull, infinity).

complete(UUID) ->
    gen_server:call(?MODULE, {complete, UUID}).

alive(UUID) ->
    gen_server:call(?MODULE, {alive, UUID}).

init([]) ->
    lmq_queue:start(),
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call({push, Data}, _From, S=#state{}) ->
    R = lmq_queue:enqueue(Data),
    case queue:is_empty(S#state.queue) of
        true  -> {reply, R, S};
        false -> {reply, R, S, lmq_queue:waittime()}
    end;
handle_call(pull, From={Pid, _}, S=#state{refs=R, queue=Q}) ->
    Ref = erlang:monitor(process, Pid),
    NewState = S#state{refs=gb_sets:add(Ref, R), queue=queue:in({From, Ref}, Q)},
    {noreply, NewState, lmq_queue:waittime()};
handle_call({complete, UUID}, _From, S=#state{}) ->
    R = lmq_queue:complete(UUID),
    {reply, R, S};
handle_call({alive, UUID}, _From, S=#state{}) ->
    R = lmq_queue:reset_timeout(UUID),
    {reply, R, S};
handle_call(stop, _From, S=#state{}) ->
    {stop, normal, ok, S}.

handle_cast(Msg, S=#state{}) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, S}.

handle_info(timeout, S=#state{}) ->
    NewState = maybe_push_message(S),
    case queue:is_empty(NewState#state.queue) of
        true  -> {noreply, NewState};
        false -> {noreply, NewState, lmq_queue:waittime()}
    end;
handle_info({'DOWN', Ref, process, _Pid, _}, S=#state{refs=R, queue=Q}) ->
    case gb_sets:is_member(Ref, R) of
        true ->
            erlang:demonitor(Ref, [flush]),
            NewQueue = queue:filter(
                fun({_, V}) when V =:= Ref -> false;
                   (_) -> true
                end, Q),
            {noreply, S#state{refs=gb_sets:delete(Ref, R), queue=NewQueue}};
        false ->
            {noreply, S}
    end;
handle_info(Msg, S=#state{}) ->
    io:format("Unknown message received: ~p~n", [Msg]),
    {noreply, S}.

terminate(_Reason, _State) ->
    ok.

maybe_push_message(S=#state{refs=R, queue=Q}) ->
    case queue:is_empty(Q) of
        true -> S;
        false ->
            case lmq_queue:dequeue() of
                empty -> S;
                Msg ->
                    case queue:out(Q) of
                        {{value, {From, Ref}}, NewQueue} ->
                            erlang:demonitor(Ref, [flush]),
                            NewRefs = gb_sets:delete(Ref, R),
                            gen_server:reply(From, Msg),
                            S#state{refs=NewRefs, queue=NewQueue};
                        {empty, Q} ->
                            S
                    end
            end
    end.
