-module(lmq_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([pull/1, update_props/1, properties/1]).

all() ->
    [pull, update_props, properties].

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

update_props(Config) ->
    Name = ?config(qname, Config),
    true = is_pid(lmq:update_props(Name, [{retry, 1}, {timeout, 0}])),
    ok = lmq:push(Name, 1),
    {[{<<"id">>, _}, {<<"content">>, 1}]} = lmq:pull(Name),
    {[{<<"id">>, _}, {<<"content">>, 1}]} = lmq:pull(Name),
    <<"empty">> = lmq:pull(Name, 0),

    %% change retry count
    true = is_pid(lmq:update_props(Name, [{retry, 0}])),
    ok = lmq:push(Name, 2),
    {[{<<"id">>, _}, {<<"content">>, 2}]} = lmq:pull(Name),
    <<"empty">> = lmq:pull(Name, 0).

properties(_Config) ->
    N1 = lmq_properies_test_q1,
    N2 = lmq_properies_test_q2,
    N3 = lmq_properies_test_q3,
    P1 = lmq_misc:extend([{retry, 0}], ?DEFAULT_QUEUE_PROPS),
    P2 = lmq_misc:extend([{retry, 1}, {timeout, 0}], ?DEFAULT_QUEUE_PROPS),
    P3 = lmq_misc:extend([{retry, 0}, {timeout, 0}], ?DEFAULT_QUEUE_PROPS),

    ok = lmq:push(N1, 1),
    Q1 = lmq_queue_mgr:get(N1),
    Q2 = lmq:update_props(N2),
    Q3 = lmq:update_props(N3, [{retry, 0}]),
    ?DEFAULT_QUEUE_PROPS = lmq_queue:get_properties(Q1),
    ?DEFAULT_QUEUE_PROPS = lmq_queue:get_properties(Q2),
    P1 = lmq_queue:get_properties(Q3),

    lmq:set_default_props([{".*", [{retry, 1}, {timeout, 0}]}]),
    timer:sleep(50),
    P2 = lmq_queue:get_properties(Q1),
    P2 = lmq_queue:get_properties(Q2),
    P3 = lmq_queue:get_properties(Q3).
