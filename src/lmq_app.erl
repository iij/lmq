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
    maybe_join(application:get_env(join)),
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
        {'_', [{"/messages", lmq_cow_msg, [multi]},
               {"/messages/:name", lmq_cow_msg, []},
               {"/messages/:name/:id", lmq_cow_reply, []},
               {"/queues/:name", lmq_cow_queue, []},
               {"/properties", lmq_cow_prop, []},
               {"/properties/:name", lmq_cow_prop, []}
              ]}
    ]),

    {ok, Ip2} = inet_parse:address(Ip),
    cowboy:start_http(lmq_http_listener, 100,
        [{ip, Ip2}, {port, Port}],
        [{env, [{dispatch, Dispatch}]},
         {max_keepalive, 10000}]
    ).

maybe_join(undefined) ->
    ok = lmq_lib:init_mnesia();
maybe_join({ok, Node}) ->
    case {net_kernel:connect_node(Node), net_adm:ping(Node)} of
        {true, pong} ->
            rpc:call(Node, lmq_console, add_new_node, [node()]);
        {_, pang} ->
            ok = lmq_lib:init_mnesia()
    end.
