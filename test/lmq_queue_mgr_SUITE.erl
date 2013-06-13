-module(lmq_queue_mgr_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([creation/1]).

all() ->
    [creation].

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
    {ok, Q1} = lmq_queue_mgr:create("q1"),
    {ok, Q2} = lmq_queue_mgr:create(q2),
    R1 = make_ref(), R2 = make_ref(),
    lmq_queue:push(Q1, R1),
    lmq_queue:push(Q2, R2),
    M2 = lmq_queue:pull(Q2),
    M1 = lmq_queue:pull(Q1),
    R1 = M1#message.data,
    R2 = M2#message.data.
