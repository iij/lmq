-module(lmq_queue_mgr_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([creation/1, match/1, restart_queue/1]).

all() ->
    [creation, match, restart_queue].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    lmq:install([node()]),
    application:start(mnesia),
    application:start(lmq),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]).

init_per_testcase(_, Config) ->
    {ok, _} = lmq_queue_supersup:start_link(),
    Config.

end_per_testcase(_, _Config) ->
    ok.

creation(_Config) ->
    ok = lmq_queue_mgr:create("q1"),
    ok = lmq_queue_mgr:create(q2),
    Q1 = lmq_queue_mgr:find("q1"),
    Q2 = lmq_queue_mgr:find(q2),
    R1 = make_ref(), R2 = make_ref(),
    lmq_queue:push(Q1, R1),
    lmq_queue:push(Q2, R2),
    M2 = lmq_queue:pull(Q2),
    M1 = lmq_queue:pull(Q1),
    R1 = M1#message.data,
    R2 = M2#message.data.

match(_Config) ->
    ok = lmq_queue_mgr:create("foo/bar"),
    ok = lmq_queue_mgr:create("foo"),
    ok = lmq_queue_mgr:create("foo/baz"),
    Q1 = lmq_queue_mgr:find('foo/bar'),
    Q2 = lmq_queue_mgr:find('foo/baz'),
    R = lmq_queue_mgr:match("^foo/.*"),
    true = lists:sort([Q1, Q2]) =:= lists:sort(R),
    %% error case
    [] = lmq_queue_mgr:match("AAA"),
    {error, invalid_regexp} = lmq_queue_mgr:match("a[1-").

restart_queue(_Config) ->
    ok = lmq_queue_mgr:create(test),
    Q1 = lmq_queue_mgr:find(test),
    exit(Q1, kill),
    timer:sleep(50), % sleep until DOWN message handled
    Q2 = lmq_queue_mgr:find(test),
    true = Q1 =/= Q2.
