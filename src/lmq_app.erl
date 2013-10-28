-module(lmq_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

-define(MSGPACK_SERV, msgpack_serv).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    {ok, Port} = application:get_env(port),
    {ok, Http} = application:get_env(http),
    ok = lmq_lib:init_mnesia(),
    R = lmq_sup:start_link(),
    start_cowboy(Http),
    {ok, _} = msgpack_rpc_server:start(?MSGPACK_SERV, tcp, lmq_api, [{port, Port}]),
    R.

stop(_State) ->
    msgpack_rpc_server:stop(?MSGPACK_SERV),
    ok.

%% ==================================================================
%% Private functions
%% ==================================================================

start_cowboy({Ip, Port}) ->
    Dispatch = cowboy_router:compile([
        {'_', [{"/msgs", lmq_cow_multi, []},
               {"/msgs/:name", lmq_cow_queue, [msg]},
               {"/msgs/:name/:id", lmq_cow_message, []},
               {"/queues/:name", lmq_cow_queue, [queue]},
               {"/props", lmq_cow_prop, []},
               {"/props/:name", lmq_cow_prop, []}
              ]}
    ]),

    {ok, Ip2} = inet_parse:address(Ip),
    cowboy:start_http(lmq_http_listener, 100,
        [{ip, Ip2}, {port, Port}],
        [{env, [{dispatch, Dispatch}]}]
    ).
