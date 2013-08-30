-module(lmq_queue_mgr_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([creation/1, creation_with_props/1, find/1, match/1, restart_queue/1,
    auto_load/1]).

all() ->
    [creation, creation_with_props, match, restart_queue, auto_load].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    lmq_lib:init_mnesia(),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]).

init_per_testcase(auto_load, Config) ->
    Config;
init_per_testcase(_, Config) ->
    {ok, _} = lmq_queue_supersup:start_link(),
    Config.

end_per_testcase(_, _Config) ->
    ok.

creation(_Config) ->
    ok = lmq_queue_mgr:create(q1),
    ok = lmq_queue_mgr:create(q2),
    Q1 = lmq_queue_mgr:find(q1),
    Q2 = lmq_queue_mgr:find(q2),
    R1 = make_ref(), R2 = make_ref(),
    lmq_queue:push(Q1, R1),
    lmq_queue:push(Q2, R2),
    M2 = lmq_queue:pull(Q2),
    M1 = lmq_queue:pull(Q1),
    R1 = M1#message.data,
    R2 = M2#message.data.

creation_with_props(_Config) ->
    ok = lmq_queue_mgr:create(qwp, [{timeout, 1}]),
    true = is_pid(lmq_queue_mgr:find(qwp)),
    Props = lmq_lib:queue_info(qwp),
    1 = proplists:get_value(timeout, Props),
    2 = proplists:get_value(retry, Props).

find(_Config) ->
    not_found = lmq_queue_mgr:find('find/a'),
    true = is_pid(lmq_queue_mgr:find('find/a', [create])),
    ?DEFAULT_QUEUE_PROPS = lmq_lib:queue_info('find/a'),

    %% ensure do not override props if exists
    Props = lib_misc:extend([{retry, infinity}], ?DEFAULT_QUEUE_PROPS),
    true = is_pid(lmq_queue_mgr:find('find/a', [create, {props, Props}])),
    ?DEFAULT_QUEUE_PROPS = lmq_lib:queue_info('find/a'),

    %% ensure override props if setting update flag
    true = is_pid(lmq_queue_mgr:find('find/a', [update, {props, Props}])),
    Props = lmq_lib:queue_info('find/a'),

    %% ensure custom props can be set
    true = is_pid(lmq_queue_mgr:find('find/b', [create, {props, Props}])),
    Props = lmq_lib:queue_info('find/b').

match(_Config) ->
    ok = lmq_queue_mgr:create('foo/bar'),
    ok = lmq_queue_mgr:create(foo),
    ok = lmq_queue_mgr:create('foo/baz'),
    Q1 = lmq_queue_mgr:find('foo/bar'),
    Q2 = lmq_queue_mgr:find('foo/baz'),
    R = lmq_queue_mgr:match("^foo/.*"),
    R = lmq_queue_mgr:match(<<"^foo/.*">>),
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

auto_load(_Config) ->
    lmq_lib:create(auto_loaded_1),
    lmq_lib:create(auto_loaded_2),
    {ok, _} = lmq_queue_supersup:start_link(),
    timer:sleep(100), % wait until queue will be started
    true = is_pid(lmq_queue_mgr:find('auto_loaded_1')),
    true = is_pid(lmq_queue_mgr:find('auto_loaded_2')),
    not_found = lmq_queue_mgr:find('auto_loaded_3').
