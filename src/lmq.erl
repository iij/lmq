-module(lmq).

-include("lmq.hrl").
-export([install/1, start/0, stop/0]).

install(Nodes) ->
    ok = mnesia:create_schema(Nodes),
    rpc:multicall(Nodes, application, start, [mnesia]),
    %% TODO: create admin table here
    rpc:multicall(Nodes, application, stop, [mnesia]).

start() ->
    ok = application:start(mnesia),
    ok = application:start(ranch),
    ok = application:start(lmq).

stop() ->
    ok = application:stop(lmq),
    ok = application:stop(ranch),
    ok = application:stop(mnesia).
