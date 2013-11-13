-module(lmq_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push/1, pull/1, update_props/1, properties/1, status/1, stats/1]).

all() ->
    [push, pull, update_props, properties, status, stats].

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

push(Config) ->
    Name = ?config(qname, Config),
    lmq:push(atom_to_binary(Name, latin1), <<"test 1">>),
    lmq:push(atom_to_binary(Name, latin1),
        [{<<"content-type">>, <<"text/plain">>}], <<"test 2">>),
    [{queue, Name}, {id, _}, {type, normal},
     {content, {[], <<"test 1">>}}] = lmq:pull(Name, 0),
    [{queue, Name}, {id, _}, {type, normal},
     {content, {[{<<"content-type">>, <<"text/plain">>}], <<"test 2">>}}]
     = lmq:pull(Name, 0).

pull(Config) ->
    Name = ?config(qname, Config),
    Parent = self(),
    spawn_link(fun() -> Parent ! lmq:pull(Name) end),
    timer:sleep(100),
    lmq:push(Name, <<"test_data">>),
    receive
        [{queue, Name}, {id, _}, {type, normal}, {content, {[], <<"test_data">>}}] -> ok
    after 100 ->
        ct:fail(no_response)
    end.

update_props(Config) ->
    Name = ?config(qname, Config),
    true = is_pid(lmq:update_props(Name, [{retry, 1}, {timeout, 0}])),
    ok = lmq:push(Name, 1),
    [{queue, Name}, {id, _}, {type, normal}, {content, {[], 1}}] = lmq:pull(Name),
    [{queue, Name}, {id, _}, {type, normal}, {content, {[], 1}}] = lmq:pull(Name),
    empty = lmq:pull(Name, 0),

    %% change retry count
    true = is_pid(lmq:update_props(Name, [{retry, 0}])),
    ok = lmq:push(Name, 2),
    [{queue, Name}, {id, _}, {type, normal}, {content, {[], 2}}] = lmq:pull(Name),
    empty = lmq:pull(Name, 0).

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
    P3 = lmq_queue:get_properties(Q3),
    lmq:set_default_props([]).

status(Config) ->
    Name = ?config(qname, Config),
    Node = node(),
    Q = lmq_queue_mgr:get(Name, [create]),
    lmq_queue:push(Q, 1),
    Status = lmq:status(),
    [Node] = proplists:get_value(all_nodes, Status),
    [Node] = proplists:get_value(active_nodes, Status),
    QStatus = proplists:get_value(Name, proplists:get_value(queues, Status)),
    1 = proplists:get_value(size, QStatus),
    true = proplists:get_value(memory, QStatus) > 0,
    [Node] = proplists:get_value(nodes, QStatus),
    ?DEFAULT_QUEUE_PROPS = proplists:get_value(props, QStatus).

stats(Config) ->
    Name = ?config(qname, Config),
    Q = lmq_queue_mgr:get(Name, [create]),
    lmq_queue:push(Q, 1),
    Stats = proplists:get_value(Name, lmq:stats()),
    [push, pull, retention] = proplists:get_keys(Stats).
