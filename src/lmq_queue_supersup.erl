-module(lmq_queue_supersup).

-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link(?MODULE, []).

init([]) ->
    MgrArgs = case application:get_env(stats_interval) of
                  {ok, T} when is_integer(T), T > 0 ->
                      [[{stats_interval, T}]];
                  _ ->
                      []
              end,

    QueueSup = {lmq_queue_sup,
                {lmq_queue_sup, start_link, []},
                permanent, infinity, supervisor, [lmq_queue_sup]},

    QueueMgr = {lmq_queue_mgr,
                {lmq_queue_mgr, start_link, MgrArgs},
                permanent, 5000, worker, [lmq_queue_mgr]},

    Children = [QueueSup, QueueMgr],
    {ok, {{one_for_all, 5, 10}, Children}}.
