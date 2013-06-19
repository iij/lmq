-module(lmq_queue_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([push_pull_complete/1, return_to/1, multi_queue/1]).

all() ->
    [push_pull_complete, return_to, multi_queue].

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
    {ok, Pid} = lmq_queue:start_link(message),
    [{queue, Pid} | Config].

end_per_testcase(_, Config) ->
    lmq_queue:stop(?config(queue, Config)).

push_pull_complete(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M = lmq_queue:pull(Pid),
    {TS, UUID} = M#message.id,
    true = is_float(TS),
    true = is_binary(UUID),
    uuid:uuid_to_string(UUID),
    Ref = M#message.data,
    ok = lmq_queue:complete(Pid, UUID).

return_to(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M1 = lmq_queue:pull(Pid),
    Ref = M1#message.data,
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:return(Pid, UUID1),
    not_found = lmq_queue:return(Pid, UUID1),
    not_found = lmq_queue:complete(Pid, UUID1),
    M2 = lmq_queue:pull(Pid),
    Ref = M2#message.data,
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:complete(Pid, UUID2).

multi_queue(Config) ->
    Q1 = ?config(queue, Config),
    {ok, Q2} = lmq_queue:start_link(for_test),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    ok = lmq_queue:push(Q1, Ref1),
    ok = lmq_queue:push(Q2, Ref2),
    M2 = lmq_queue:pull(Q2), Ref2 = M2#message.data,
    M1 = lmq_queue:pull(Q1), Ref1 = M1#message.data,
    ok = lmq_queue:complete(Q1, element(2, M1#message.id)),
    ok = lmq_queue:alive(Q2, element(2, M2#message.id)),
    ok = lmq_queue:return(Q2, element(2, M2#message.id)),
    M3 = lmq_queue:pull(Q2),
    ok = lmq_queue:complete(Q2, element(2, M3#message.id)),
    ok = lmq_queue:stop(Q2).
