-module(lmq_queue_supersup).

-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link(?MODULE, []).

init([]) ->
    QueueSup = {lmq_queue_sup,
                {lmq_queue_sup, start_link, []},
                permanent, infinity, supervisor, [lmq_queue_sup]},

    QueueMgr = {lmq_queue_mgr,
                {lmq_queue_mgr, start_link, []},
                permanent, 5000, worker, [lmq_queue_mgr]},

    Children = [QueueSup, QueueMgr],
    {ok, {{one_for_all, 5, 10}, Children}}.
