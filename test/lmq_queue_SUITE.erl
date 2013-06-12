-module(lmq_queue_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([push_pull_complete/1, return_to/1]).

all() ->
    [push_pull_complete, return_to].

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
    {ok, Pid} = lmq_queue:start_link(),
    ok = lmq_lib:create(message),
    [{lmq, Pid} | Config].

end_per_testcase(_, Config) ->
    lmq_queue:stop(?config(lmq, Config)).

push_pull_complete(_Config) ->
    Ref = make_ref(),
    ok = lmq_queue:push(Ref),
    M = lmq_queue:pull(),
    {TS, UUID} = M#message.id,
    true = is_float(TS),
    uuid:string_to_uuid(UUID),
    Ref = M#message.data,
    ok = lmq_queue:complete(UUID).

return_to(_Config) ->
    Ref = make_ref(),
    ok = lmq_queue:push(Ref),
    M1 = lmq_queue:pull(),
    Ref = M1#message.data,
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:return(UUID1),
    not_found = lmq_queue:return(UUID1),
    not_found = lmq_queue:complete(UUID1),
    M2 = lmq_queue:pull(),
    Ref = M2#message.data,
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:complete(UUID2).
