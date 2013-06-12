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
    Name = message,
    {ok, _} = lmq_queue:start_link(Name),
    [{qname, Name} | Config].

end_per_testcase(_, Config) ->
    lmq_queue:stop(?config(qname, Config)).

push_pull_complete(Config) ->
    Name = ?config(qname, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Name, Ref),
    M = lmq_queue:pull(Name),
    {TS, UUID} = M#message.id,
    true = is_float(TS),
    uuid:string_to_uuid(UUID),
    Ref = M#message.data,
    ok = lmq_queue:complete(Name, UUID).

return_to(Config) ->
    Name = ?config(qname, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Name, Ref),
    M1 = lmq_queue:pull(Name),
    Ref = M1#message.data,
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:return(Name, UUID1),
    not_found = lmq_queue:return(Name, UUID1),
    not_found = lmq_queue:complete(Name, UUID1),
    M2 = lmq_queue:pull(Name),
    Ref = M2#message.data,
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:complete(Name, UUID2).

multi_queue(Config) ->
    Name1 = ?config(qname, Config),
    Name2 = for_test,
    {ok, _} = lmq_queue:start_link(Name2),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    ok = lmq_queue:push(Name1, Ref1),
    ok = lmq_queue:push(Name2, Ref2),
    M2 = lmq_queue:pull(Name2), Ref2 = M2#message.data,
    M1 = lmq_queue:pull(Name1), Ref1 = M1#message.data,
    ok = lmq_queue:complete(Name1, element(2, M1#message.id)),
    ok = lmq_queue:alive(Name2, element(2, M2#message.id)),
    ok = lmq_queue:return(Name2, element(2, M2#message.id)),
    M3 = lmq_queue:pull(Name2),
    ok = lmq_queue:complete(Name2, element(2, M3#message.id)),
    ok = lmq_queue:stop(Name2).
