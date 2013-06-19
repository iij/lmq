-module(lmq).

-include("lmq.hrl").
-export([install/1, start/0, stop/0]).

-define(DEPS, [crypto, quickrand, uuid, msgpack, msgpack_rpc,
    mnesia, ranch, lmq]).

install(Nodes) ->
    ok = mnesia:create_schema(Nodes),
    rpc:multicall(Nodes, application, start, [mnesia]),
    %% TODO: create admin table here
    rpc:multicall(Nodes, application, stop, [mnesia]).

start() ->
    [ensure_started(Dep) || Dep <- ?DEPS],
    ok.

stop() ->
    [application:stop(Dep) || Dep <- lists:reverse(?DEPS)],
    ok.

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.
