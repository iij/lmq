-module(lmq_lib_SUITE).

-include("lmq.hrl").
-include("lmq_test.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([lmq_info/1, create_delete/1, queue_names/1, done/1, release/1, retain/1, waittime/1,
    limit_retry/1, error_case/1, accumlate/1, property/1, many_waste_messages/1]).
-export([enqueue_many/2]).

all() ->
    [lmq_info, create_delete, queue_names, done, release, retain, waittime, limit_retry,
     error_case, accumlate, property, many_waste_messages].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    application:start(folsom),
    ok = lmq_lib:init_mnesia(),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(create_delete, Config) ->
    lmq_event:start_link(),
    lmq_event:add_handler(lmq_test_handler, self()),
    Config;

init_per_testcase(_, Config) ->
    lmq_event:start_link(),
    lmq_event:add_handler(lmq_test_handler, self()),
    Name = test,
    lmq_lib:create(Name),
    [{qname, Name} | Config].

end_per_testcase(_, Config) ->
    ok = lmq_lib:delete(?config(qname, Config)).

lmq_info(_Config) ->
    ok = lmq_lib:set_lmq_info(name, lmq),
    {ok, lmq} = lmq_lib:get_lmq_info(name),
    {error, not_found} = lmq_lib:get_lmq_info(non_exists),
    {ok, []} = lmq_lib:get_lmq_info(non_exists, []).

create_delete(_Config) ->
    %% create new queue
    ok = lmq_lib:create(test),
    message = mnesia:table_info(test, record_name),
    [] = lmq_lib:queue_info(test),
    ?EVENT_OR_FAIL({local, {queue_created, test}}),

    %% update properties
    ok = lmq_lib:create(test, [{timeout, 10}]),
    [{timeout, 10}] = lmq_lib:queue_info(test),
    ?EVENT_OR_FAIL({local, {queue_created, test}}),

    %% no event occurred when properties are not changed
    ok = lmq_lib:create(test, [{timeout, 10}]),
    [{timeout, 10}] = lmq_lib:queue_info(test),
    ?EVENT_AND_FAIL({local, {queue_created, test}}),

    %% delete
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
    ok = lmq_lib:enqueue(Name, make_ref(), [{retry, 2}]),
    M = lmq_lib:dequeue(Name, 30),
    2 = M#message.retry,
    {_, UUID} = M#message.id,
    ok = lmq_lib:release(Name, UUID),
    not_found = lmq_lib:release(Name, UUID),

    M1 = lmq_lib:dequeue(Name, 30),
    1 = M1#message.retry,
    ok = lmq_lib:put_back(Name, element(2, M1#message.id)),
    1 = (lmq_lib:dequeue(Name, 30))#message.retry,

    ok = lmq_lib:enqueue(Name, make_ref()),
    M2 = lmq_lib:dequeue(Name, 30),
    infinity = M2#message.retry,
    ok = lmq_lib:release(Name, element(2, M2#message.id)),
    infinity = (lmq_lib:dequeue(Name, 30))#message.retry.

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
    lists:all(fun(M) -> Ref =:= M#message.content end,
        [lmq_lib:dequeue(Name, Timeout) || _ <- lists:seq(1, 6)]),
    empty = lmq_lib:dequeue(Name, Timeout),
    %% retry infinity
    ok = lmq_lib:enqueue(Name, Ref),
    lists:all(fun(M) -> Ref =:= M#message.content end,
        [lmq_lib:dequeue(Name, Timeout) || _ <- lists:seq(1, 10)]).

error_case(_Config) ->
    Name = '__abcdefg__',
    {error, no_queue_exists} = lmq_lib:enqueue(Name, make_ref()),
    {error, no_queue_exists} = lmq_lib:dequeue(Name, 30),
    {error, no_queue_exists} = lmq_lib:done(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:release(Name, "AAA"),
    {error, no_queue_exists} = lmq_lib:retain(Name, "AAA", 30),
    {error, no_queue_exists} = lmq_lib:waittime(Name).

accumlate(Config) ->
    Name = ?config(qname, Config),
    Timeout = 30,
    R1 = make_ref(), R2 = make_ref(), R3 = make_ref(),
    %% 0 means not accumulate
    ok = lmq_lib:enqueue(Name, R1, [{accum, 0}]),
    R1 = (lmq_lib:dequeue(Name, Timeout))#message.content,

    %% get 2 compound messages, each compound message contains 1 message
    {accum, new} = lmq_lib:enqueue(Name, R1, [{accum, 1}]), timer:sleep(1),
    {accum, new} = lmq_lib:enqueue(Name, R2, [{accum, 1}]), timer:sleep(1),
    [R1] = (lmq_lib:dequeue(Name, Timeout))#message.content,
    [R2] = (lmq_lib:dequeue(Name, Timeout))#message.content,

    %% accumulate and no accumulate message
    {accum, new} = lmq_lib:enqueue(Name, R1, [{accum, 100}]),
    {accum, yes} = lmq_lib:enqueue(Name, R2, [{accum, 100}]),
    ok = lmq_lib:enqueue(Name, R3),
    R3 = (lmq_lib:dequeue(Name, Timeout))#message.content,
    empty = lmq_lib:dequeue(Name, Timeout),
    timer:sleep(100),
    [R1, R2] = (lmq_lib:dequeue(Name, Timeout))#message.content.

property(_Config) ->
    N1 = property_default,
    N2 = property_override1,
    N3 = property_override2,
    P1 = ?DEFAULT_QUEUE_PROPS,
    P2 = lmq_misc:extend([{retry, infinity}, {timeout, 0}], ?DEFAULT_QUEUE_PROPS),
    P3 = lmq_misc:extend([{retry, 0}, {timeout, 0}], ?DEFAULT_QUEUE_PROPS),

    lmq_lib:create(N1),
    lmq_lib:create(N2),
    lmq_lib:create(N3, [{retry, 0}]),
    lmq_lib:set_lmq_info(default_props,
        [{"override", [{retry, infinity}, {timeout, 0}]}]),

    P1 = lmq_lib:get_properties(N1),
    P2 = lmq_lib:get_properties(N2),
    P3 = lmq_lib:get_properties(N3),
    P3 = lmq_lib:get_properties(N2, [{retry, 0}]),

    P4 = lmq_misc:extend([{accum, 1}], ?DEFAULT_QUEUE_PROPS),
    P5 = lmq_misc:extend([{accum, 1}, {retry, 0}], ?DEFAULT_QUEUE_PROPS),
    lmq_lib:set_lmq_info(default_props, [{"override", [{accum, 1}]}]),
    P1 = lmq_lib:get_properties(N1),
    P4 = lmq_lib:get_properties(N2),
    P5 = lmq_lib:get_properties(N3).

many_waste_messages(Config) ->
    Name = ?config(qname, Config),
    rpc:pmap({?MODULE, enqueue_many}, [Name], lists:seq(1, 10)),
    ct:timetrap(10000),
    empty = lmq_lib:dequeue(Name, 0).

enqueue_many(I, Name) ->
    [lmq_lib:enqueue(Name, I*N, [{retry, -1}]) || N <- lists:seq(1, 1000)].
