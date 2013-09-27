-module(lmq_mpull_sup).

-behaviour(supervisor).

-export([init/1]).
-export([start_link/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    MaxRestart = 5,
    MaxTime = 3600,
    {ok, {{simple_one_for_one, MaxRestart, MaxTime},
          [{lmq_mpull,
           {lmq_mpull, start_link, []},
           temporary,
           5000,
           worker,
           [lmq_mpull]}]}}.
