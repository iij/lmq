-module(lmq_msgpack_SUITE).

-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull_done/1, release/1, props_and_timeout/1, packed_queue/1,
    push_all/1, pull_any/1]).

all() ->
    [push_pull_done, release, props_and_timeout, packed_queue, push_all, pull_any].

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
    lmq_queue_mgr:delete(binary_to_atom(Name, latin1)).

push_pull_done(Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    Content = <<"test data">>,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, create, [Name]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, Content]),
    {ok, Res} = msgpack_rpc_client:call(Client, pull, [Name]),
    {[{<<"id">>, UUID}, {<<"content">>, Content}]} = Res,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, retain, [Name, UUID]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, done, [Name, UUID]).

release(Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    Content = <<"test data 2">>,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, create, [Name]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, Content]),
    {ok, Res} = msgpack_rpc_client:call(Client, pull, [Name]),
    {[{<<"id">>, UUID}, {<<"content">>, Content}]} = Res,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, release, [Name, UUID]),
    {error, _} = msgpack_rpc_client:call(Client, done, [Name, UUID]),
    {ok, Res1} = msgpack_rpc_client:call(Client, pull, [Name]),
    {[{<<"id">>, UUID1}, {<<"content">>, Content}]} = Res1,
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, done, [Name, UUID1]).

props_and_timeout(Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    Props = {[{<<"retry">>, 0}, {<<"timeout">>, 0}]},
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, create, [Name, Props]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, <<"test">>]),
    {ok, Res} = msgpack_rpc_client:call(Client, pull, [Name, 0.2]),
    {[{<<"id">>, _UUID}, {<<"content">>, <<"test">>}]} = Res,
    {ok, <<"empty">>} = msgpack_rpc_client:call(Client, pull, [Name, 0.2]).

packed_queue(Config) ->
    Client = ?config(client, Config),
    Name = ?config(qname, Config),
    Props = {[{<<"timeout">>, 0.4}, {<<"pack">>, 0.2}]},
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, create, [Name, Props]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, 1]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, 2]),
    {ok, <<"empty">>} = msgpack_rpc_client:call(Client, pull, [Name, 0]),
    timer:sleep(200),
    {ok, {[{<<"id">>, _}, {<<"content">>, [1, 2]}]}} =
        msgpack_rpc_client:call(Client, pull, [Name, 0]),
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push, [Name, 3]),
    timer:sleep(400),
    {ok, {[{<<"id">>, _}, {<<"content">>, [3]}]}} =
        msgpack_rpc_client:call(Client, pull, [Name, 0]),
    {ok, {[{<<"id">>, _}, {<<"content">>, [1, 2]}]}} =
        msgpack_rpc_client:call(Client, pull, [Name, 0]).

push_all(Config) ->
    Client = ?config(client, Config),
    Names = [<<"lmq/foo">>, <<"lmq/bar">>],
    [msgpack_rpc_client:call(Client, create, [Name]) || Name <- Names],
    {ok, <<"ok">>} = msgpack_rpc_client:call(Client, push_all, [<<"lmq/.*">>, <<"data">>]),
    {ok, {[{<<"id">>, _}, {<<"content">>, <<"data">>}]}} =
        msgpack_rpc_client:call(Client, pull, [<<"lmq/foo">>, 0]),
    {ok, {[{<<"id">>, _}, {<<"content">>, <<"data">>}]}} =
        msgpack_rpc_client:call(Client, pull, [<<"lmq/bar">>, 0]),
    [lmq_queue_mgr:delete(binary_to_atom(N, latin1)) || N <- Names].

pull_any(Config) ->
    Client = ?config(client, Config),
    Names = [<<"lmq/foo">>, <<"lmq/bar">>],
    [msgpack_rpc_client:call(Client, create, [Name]) || Name <- Names],
    [msgpack_rpc_client:call(Client, push, [Name, Name]) || Name <- Names],
    {ok, {[{<<"id">>, _}, {<<"content">>, R1}]}} =
        msgpack_rpc_client:call(Client, pull_any, [<<"lmq/.*">>, 0]),
    {ok, {[{<<"id">>, _}, {<<"content">>, R2}]}} =
        msgpack_rpc_client:call(Client, pull_any, [<<"lmq/.*">>, 0.2]),
    true = lists:sort([R1, R2]) =:= lists:sort(Names),
    {ok, <<"empty">>} =
        msgpack_rpc_client:call(Client, pull_any, [<<"lmq/.*">>, 0]),
    {ok, <<"empty">>} =
        msgpack_rpc_client:call(Client, pull_any, [<<"lmq/.*">>, 0.2]),
    [lmq_queue_mgr:delete(binary_to_atom(N, latin1)) || N <- Names].
