-module(lmq_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(CHILD(I, Type, Args), {I, {I, start_link, Args}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, InfluxDB} = application:get_env(influxdb),
    Host = proplists:get_value(host, InfluxDB),
    Port = proplists:get_value(port, InfluxDB),

    {ok, {{one_for_all, 5, 10},
          [?CHILD(lmq_event, worker),
           ?CHILD(lmq_hook, worker),
           ?CHILD(lmq_queue_supersup, supervisor),
           ?CHILD(lmq_mpull_sup, supervisor),
           ?CHILD(influxdb_client, worker, [Host, Port])]}}.
