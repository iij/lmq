-module(lmq_lib_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([lmq_info/1, create_delete/1, queue_names/1, done/1, release/1, retain/1, waittime/1,
    limit_retry/1, error_case/1, packing/1]).

all() ->
    [lmq_info, create_delete, queue_names, done, release, retain, waittime, limit_retry,
     error_case, packing].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    ok = lmq_lib:init_mnesia(),
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

lmq_info(_Config) ->
    ok = lmq_lib:set_lmq_info(name, lmq),
    {ok, lmq} = lmq_lib:get_lmq_info(name),
    {error, not_found} = lmq_lib:get_lmq_info(non_exists).

create_delete(_Config) ->
    ok = lmq_lib:create(test),
    message = mnesia:table_info(test, record_name),
    ?DEFAULT_QUEUE_PROPS = lmq_lib:queue_info(test),
    ok = lmq_lib:create(test, [{timeout, 10}]),
    Props = lmq_lib:queue_info(test),
    10 = proplists:get_value(timeout, Props),
    2 = proplists:get_value(retry, Props),
    ok = lmq_lib:delete(test),
    {aborted, {no_exists, _}} = mnesia:delete_table(test),
    not_found = lmq_lib:queue_info(test),
    ok = lmq_lib:delete(test).

queue_names(Config) ->
    Name = fooooo,
    lmq_lib:create(Name),
    true = lists:sort([?config(qname, Config), Name]) =:=
        lists:sort(lmq_lib:all_queue_names()),
    lmq_lib:delete(Name).

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
    empty = lmq_lib:first(Name),
    infinity = lmq_lib:waittime(Name),
    ok = lmq_lib:enqueue(Name, make_ref()),
    0 = lmq_lib:waittime(Name),
    lmq_lib:dequeue(Name, 30),
    true = 29500 < lmq_lib:waittime(Name).

limit_retry(Config) ->
    Name = ?config(qname, Config),
    Timeout = 0,
    Ref = make_ref(),
    %% retry 5 times, that means dequeue succeed 6 times
    ok = lmq_lib:enqueue(Name, Ref, [{retry, 5}]),
    lists:all(fun(M) -> Ref =:= M#message.data end,
        [lmq_lib:dequeue(Name, Timeout) || _ <- lists:seq(1, 6)]),
    empty = lmq_lib:dequeue(Name, Timeout),
    %% retry infinity
    ok = lmq_lib:enqueue(Name, Ref),
    lists:all(fun(M) -> Ref =:= M#message.data end,
        [lmq_lib:dequeue(Name, Timeout) || _ <- lists:seq(1, 10)]).

error_case(_Config) ->
    Name = '__abcdefg__',
    {error, no_queue_exists} = lmq_lib:enqueue(Name, make_ref()),
    {error, no_queue_exists} = lmq_lib:dequeue(Name, 30),
    {error, no_queue_exists} = lmq_lib:done(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:release(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:retain(Name, "AAA", 30),
    {error, no_queue_exists} = lmq_lib:waittime(Name).

packing(Config) ->
    Name = ?config(qname, Config),
    Timeout = 30,
    R1 = make_ref(), R2 = make_ref(), R3 = make_ref(),
    %% 0 means not packing
    lmq_lib:enqueue(Name, R1, [{pack, 0}]),
    R1 = (lmq_lib:dequeue(Name, Timeout))#message.data,

    %% get 2 packages, each package contains 1 message
    lmq_lib:enqueue(Name, R1, [{pack, 1}]), timer:sleep(1),
    lmq_lib:enqueue(Name, R2, [{pack, 1}]), timer:sleep(1),
    [R1] = (lmq_lib:dequeue(Name, Timeout))#message.data,
    [R2] = (lmq_lib:dequeue(Name, Timeout))#message.data,

    %% packing and no packing message
    lmq_lib:enqueue(Name, R1, [{pack, 100}]),
    lmq_lib:enqueue(Name, R2, [{pack, 100}]),
    lmq_lib:enqueue(Name, R3),
    R3 = (lmq_lib:dequeue(Name, Timeout))#message.data,
    empty = lmq_lib:dequeue(Name, Timeout),
    timer:sleep(100),
    [R1, R2] = (lmq_lib:dequeue(Name, Timeout))#message.data.
