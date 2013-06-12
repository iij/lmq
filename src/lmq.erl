-module(lmq).

-include("lmq.hrl").
-export([install/1]).

install(Nodes) ->
    ok = mnesia:create_schema(Nodes),
    rpc:multicall(Nodes, application, start, [mnesia]),
    %% TODO: create admin table here
    rpc:multicall(Nodes, application, stop, [mnesia]).
