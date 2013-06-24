-module(lmq_queue_supersup).

-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link(?MODULE, []).

init([]) ->
    MaxRestart = 3,
    MaxTime = 60,
    {ok, {{one_for_all, MaxRestart, MaxTime},
          [{lmq_queue_mgr,
           {lmq_queue_mgr, start_link, [self()]},
           permanent,
           5000,
           worker,
           [lmq_queue_mgr]}]}}.
