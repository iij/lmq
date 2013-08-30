-module(lmq_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([pull/1, set_props/1]).

all() ->
    [pull, set_props].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    lmq:start(),
    Config.

end_per_suite(_Config) ->
    lmq:stop(),
    mnesia:delete_schema([node()]).

init_per_testcase(_, Config) ->
    [{qname, lmq_test} | Config].

end_per_testcase(_, Config) ->
    Name = ?config(qname, Config),
    lmq_queue_mgr:delete(Name).

pull(Config) ->
    Name = ?config(qname, Config),
    Parent = self(),
    spawn_link(fun() -> Parent ! lmq:pull(Name) end),
    timer:sleep(100),
    lmq:push(Name, <<"test_data">>),
    receive
        {[{<<"id">>, _}, {<<"content">>, <<"test_data">>}]} -> ok
    after 100 ->
        ct:fail(no_response)
    end.

set_props(Config) ->
    Name = ?config(qname, Config),
    Props = lmq_misc:extend([{retry, 1}, {timeout, 0}], ?DEFAULT_QUEUE_PROPS),
    true = is_pid(lmq:set_props(Name, Props)),
    ok = lmq:push(Name, 1),
    {[{<<"id">>, _}, {<<"content">>, 1}]} = lmq:pull(Name),
    {[{<<"id">>, _}, {<<"content">>, 1}]} = lmq:pull(Name),
    <<"empty">> = lmq:pull(Name, 0),

    %% change retry count
    Props1 = lmq_misc:extend([{retry, 0}], Props),
    true = is_pid(lmq:set_props(Name, Props1)),
    ok = lmq:push(Name, 2),
    {[{<<"id">>, _}, {<<"content">>, 2}]} = lmq:pull(Name),
    <<"empty">> = lmq:pull(Name, 0).
