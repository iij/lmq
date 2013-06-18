-module(lmq_msgpack_SUITE).

-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull_complete/1]).

all() ->
    [push_pull_complete].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    lmq:install([node()]),
    lmq:start(),
    Config.

end_per_suite(_Config) ->
    lmq:stop(),
    mnesia:delete_schema([node()]).

init_per_testcase(_, Config) ->
    {ok, Pid} = msgpack_rpc_client:connect(tcp, "localhost", 18800, []),
    [{client, Pid}, {qname, <<"msgpack_test">>} | Config].

end_per_testcase(_, Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    msgpack_rpc_client:close(Client),
    mnesia:delete_table(binary_to_atom(Name, latin1)).

push_pull_complete(Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    Content = <<"test data">>,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, create, [Name]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, Content]),
    {ok, Res} = msgpack_rpc_client:call(Client, pull, [Name]),
    {[{<<"id">>, UUID}, {<<"content">>, Content}]} = Res,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, complete, [Name, UUID]).
