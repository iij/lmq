-module(lmq_lib_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([create_delete/1, done/1, release/1, retain/1, waittime/1, error_case/1]).

all() ->
    [create_delete, done, release, retain, waittime, error_case].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    lmq:install([node()]),
    application:start(mnesia),
    application:start(lmq),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(create_delete, Config) ->
    Config;
init_per_testcase(_, Config) ->
    Name = test,
    lmq_lib:create(Name),
    [{qname, Name} | Config].

end_per_testcase(_, Config) ->
    ok = lmq_lib:delete(?config(qname, Config)).

create_delete(_Config) ->
    ok = lmq_lib:create(test),
    message = mnesia:table_info(test, record_name),
    ?DEFAULT_QUEUE_PROPS = lmq_lib:queue_info(test),
    ok = lmq_lib:create(test, [{timeout, 10}]),
    [{timeout, 10}] = lmq_lib:queue_info(test),
    ok = lmq_lib:delete(test),
    {aborted, {no_exists, _}} = mnesia:delete_table(test),
    not_found = lmq_lib:queue_info(test),
    ok = lmq_lib:delete(test).

done(Config) ->
    Name = ?config(qname, Config),
    ok = lmq_lib:enqueue(Name, make_ref()),
    Now = lmq_misc:unixtime(),
    M = lmq_lib:dequeue(Name, 10),
    {TS, UUID} = M#message.id,
    true = Now < TS andalso TS - Now - 10 < 1,
    ok = lmq_lib:done(Name, UUID),
    not_found = lmq_lib:done(Name, UUID).

release(Config) ->
    Name = ?config(qname, Config),
    ok = lmq_lib:enqueue(Name, make_ref()),
    M = lmq_lib:dequeue(Name, 30),
    {_, UUID} = M#message.id,
    ok = lmq_lib:release(Name, UUID),
    not_found = lmq_lib:release(Name, UUID).

retain(Config) ->
    Name = ?config(qname, Config),
    ok = lmq_lib:enqueue(Name, make_ref()),
    Now = lmq_misc:unixtime(),
    M = lmq_lib:dequeue(Name, 15),
    {TS, UUID} = M#message.id,
    true = Now < TS andalso TS - Now - 15 < 1,
    ok = lmq_lib:retain(Name, UUID, 30),
    not_found = lmq_lib:retain(Name, "AAA", 30).

waittime(Config) ->
    Name = ?config(qname, Config),
    empty =lmq_lib:first(Name),
    infinity = lmq_lib:waittime(Name),
    ok = lmq_lib:enqueue(Name, make_ref()),
    0 = lmq_lib:waittime(Name),
    lmq_lib:dequeue(Name, 30),
    true = 0 < lmq_lib:waittime(Name).

error_case(_Config) ->
    Name = '__abcdefg__',
    {error, no_queue_exists} = lmq_lib:enqueue(Name, make_ref()),
    {error, no_queue_exists} = lmq_lib:dequeue(Name, 30),
    {error, no_queue_exists} = lmq_lib:done(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:release(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:retain(Name, "AAA", 30),
    {error, no_queue_exists} = lmq_lib:waittime(Name).
