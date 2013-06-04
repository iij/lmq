-module(lmq_queue_server).
-behaviour(gen_server).
-compile(export_all).

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
    {ok, []}.

handle_call({push, Data}, _From, Puller) ->
    R = lmq_queue:enqueue(Data),
    gen_server:cast(?MODULE, notify),
    {reply, R, Puller};
handle_call(pull, From, Puller) ->
    case lmq_queue:dequeue() of
        empty ->
            Pid = spawn_link(?MODULE, delay_response, [self(), From]),
            {noreply, [Pid|Puller]};
        Message ->
            {reply, Message, Puller}
    end;
handle_call({complete, UUID}, _From, Puller) ->
    R = lmq_queue:complete(UUID),
    {reply, R, Puller};
handle_call({alive, UUID}, _From, Puller) ->
    R = lmq_queue:reset_timeout(UUID),
    {reply, R, Puller};
handle_call(stop, _From, Puller) ->
    {stop, normal, ok, Puller}.

handle_cast(notify, Puller) ->
    lists:foreach(fun(Pid) ->
        Pid ! {lmq, self(), wake}
    end, Puller),
    {noreply, Puller}.

handle_info({'EXIT', Pid, Reason}, Puller) ->
    {noreply, Puller -- [Pid]};
handle_info(Info, Puller) ->
    io:format("unexpected message received: ~p~n", [Info]),
    {noreply, Puller}.

terminate(_Reason, _State) ->
    ok.

delay_response(SrvPid, From) ->
    {Pid, _} = From,
    link(Pid),
    Timeout = lmq_queue:waittime(),
    receive
        {lmq, SrvPid, wake} -> ok
    after Timeout ->
        ok
    end,
    case lmq_queue:dequeue() of
        empty -> delay_response(SrvPid, From);
        Message ->
            unlink(Pid),
            gen_server:reply(From, Message)
    end.
