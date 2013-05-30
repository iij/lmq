-module(lmq_queue_server).
-behaviours(gen_server).
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

init([]) ->
    lmq_queue:start(),
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
handle_call(stop, _From, Puller) ->
    {stop, normal, ok, Puller}.

handle_cast(notify, Puller) ->
    lists:foreach(fun(Pid) ->
        Pid ! {lmq, self(), wake}
    end, Puller),
    {noreply, Puller}.

terminate(_Reason, _State) ->
    ok.

delay_response(SrvPid, From) ->
    Timeout = lmq_queue:waittime(),
    receive
        {lmq, SrvPid, wake} -> ok
    after Timeout ->
        ok
    end,
    case lmq_queue:dequeue() of
        empty -> delay_response(SrvPid, From);
        Message -> gen_server:reply(From, Message)
    end.
