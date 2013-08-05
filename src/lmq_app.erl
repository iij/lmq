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
    ok = lmq_lib:init_mnesia(),
    R = lmq_sup:start_link(),
    {ok, _} = msgpack_rpc_server:start(?MSGPACK_SERV, tcp, lmq_api, [{port, Port}]),
    R.

stop(_State) ->
    msgpack_rpc_server:stop(?MSGPACK_SERV),
    ok.
