-module(lmq_queue_sup).

-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    MaxRestart = 5,
    MaxTime = 3600,
    {ok, {{simple_one_for_one, MaxRestart, MaxTime},
          [{lmq_queue,
           {lmq_queue, start_link, []},
           transient,
           5000,
           worker,
           [lmq_queue]}]}}.
