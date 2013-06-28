-module(lmq_queue_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([init/1, push_pull_done/1, release/1, multi_queue/1, pull_timeout/1]).

all() ->
    [init, push_pull_done, release, multi_queue, pull_timeout].

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

init_per_testcase(init, Config) ->
    Config;
init_per_testcase(_, Config) ->
    {ok, Pid} = lmq_queue:start_link(message),
    [{queue, Pid} | Config].

end_per_testcase(init, _Config) ->
    ok;
end_per_testcase(_, Config) ->
    lmq_queue:stop(?config(queue, Config)).

init(_Config) ->
    not_found = lmq_lib:queue_info(queue_test_1),
    {ok, Q1} = lmq_queue:start_link(queue_test_1),
    ?DEFAULT_QUEUE_PROPS = lmq_lib:queue_info(queue_test_1),
    lmq_queue:stop(Q1),
    {ok, Q2} = lmq_queue:start_link(queue_test_1, [{timeout, 10}]),
    [{timeout, 10}] = lmq_lib:queue_info(queue_test_1),
    lmq_queue:stop(Q2),
    {ok, Q3} = lmq_queue:start_link(queue_test_1),
    [{timeout, 10}] = lmq_lib:queue_info(queue_test_1),
    lmq_queue:stop(Q3).

push_pull_done(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M = lmq_queue:pull(Pid),
    {TS, UUID} = M#message.id,
    true = is_float(TS),
    true = is_binary(UUID),
    uuid:uuid_to_string(UUID),
    Ref = M#message.data,
    ok = lmq_queue:done(Pid, UUID).

release(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M1 = lmq_queue:pull(Pid),
    Ref = M1#message.data,
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:release(Pid, UUID1),
    not_found = lmq_queue:release(Pid, UUID1),
    not_found = lmq_queue:done(Pid, UUID1),
    M2 = lmq_queue:pull(Pid),
    Ref = M2#message.data,
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:done(Pid, UUID2).

multi_queue(Config) ->
    Q1 = ?config(queue, Config),
    {ok, Q2} = lmq_queue:start_link(for_test),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    ok = lmq_queue:push(Q1, Ref1),
    ok = lmq_queue:push(Q2, Ref2),
    M2 = lmq_queue:pull(Q2), Ref2 = M2#message.data,
    M1 = lmq_queue:pull(Q1), Ref1 = M1#message.data,
    ok = lmq_queue:done(Q1, element(2, M1#message.id)),
    ok = lmq_queue:retain(Q2, element(2, M2#message.id)),
    ok = lmq_queue:release(Q2, element(2, M2#message.id)),
    M3 = lmq_queue:pull(Q2),
    ok = lmq_queue:done(Q2, element(2, M3#message.id)),
    ok = lmq_queue:stop(Q2).

pull_timeout(_Config) ->
    {ok, Q} = lmq_queue:start_link(pull_timeout, [{timeout, 0.3}]),
    Ref = make_ref(),
    ok = lmq_queue:push(Q, Ref),
    M1 = lmq_queue:pull(Q), Ref = M1#message.data,
    M2 = lmq_queue:pull(Q), Ref = M2#message.data,
    true = M1 =/= M2,
    empty = lmq_queue:pull(Q, 0.2),
    M3 = lmq_queue:pull(Q, 0.2), Ref = M3#message.data.
