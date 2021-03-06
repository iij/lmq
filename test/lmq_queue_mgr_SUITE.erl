-module(lmq_queue_mgr_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([multi_queue/1, get/1, match/1, restart_queue/1, auto_load/1,
    default_props/1]).

all() ->
    [multi_queue, get, match, restart_queue, auto_load, default_props].

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
    {ok, _} = lmq_event:start_link(),
    {ok, _} = lmq_hook:start_link(),
    Config;

init_per_testcase(_, Config) ->
    {ok, _} = lmq_event:start_link(),
    {ok, _} = lmq_hook:start_link(),
    {ok, _} = lmq_queue_supersup:start_link(),
    Config.

end_per_testcase(auto_load, _Config) ->
    lmq_hook:stop(),
    mnesia:transaction(fun() -> mnesia:delete({?LMQ_INFO_TABLE, default_props}) end);

end_per_testcase(_, _Config) ->
    lmq_hook:stop().

multi_queue(_Config) ->
    Q1 = lmq_queue_mgr:get(q1, [create]),
    Q2 = lmq_queue_mgr:get(q2, [create]),
    R1 = make_ref(), R2 = make_ref(),
    lmq_queue:push(Q1, R1),
    lmq_queue:push(Q2, R2),
    M2 = lmq_queue:pull(Q2),
    M1 = lmq_queue:pull(Q1),
    R1 = M1#message.content,
    R2 = M2#message.content.

get(_Config) ->
    not_found = lmq_queue_mgr:get('get/a'),
    true = is_pid(lmq_queue_mgr:get('get/a', [create])),
    [] = lmq_lib:queue_info('get/a'),

    %% ensure do not override props if exists
    true = is_pid(lmq_queue_mgr:get('get/a', [create, {props, [{retry, infinity}]}])),
    [] = lmq_lib:queue_info('get/a'),

    %% ensure override props if setting update flag
    true = is_pid(lmq_queue_mgr:get('get/a', [update, {props, [{retry, infinity}]}])),
    [{retry, infinity}] = lmq_lib:queue_info('get/a'),

    %% ensure custom props can be set
    true = is_pid(lmq_queue_mgr:get('get/b', [create, {props, [{retry, infinity}]}])),
    [{retry, infinity}] = lmq_lib:queue_info('get/b'),

    %% ensure old props are considered when updating
    true = is_pid(lmq_queue_mgr:get('get/b', [update, {props, [{pack, 10}]}])),
    [{pack, 10}, {retry, infinity}] = lmq_lib:queue_info('get/b'),

    %% ensure do not override props if exists in mnesia
    lmq_lib:create('get/c', [{pack, 10}]),
    true = is_pid(lmq_queue_mgr:get('get/c', [create])),
    [{pack, 10}] = lmq_lib:queue_info('get/c').

match(_Config) ->
    lmq_queue_mgr:get(foo, [create]),
    Q1 = lmq_queue_mgr:get('foo/bar', [create]),
    Q2 = lmq_queue_mgr:get('foo/baz', [create]),
    R = lmq_queue_mgr:match("^foo/.*"),
    R = lmq_queue_mgr:match(<<"^foo/.*">>),
    true = lists:sort([{'foo/bar', Q1}, {'foo/baz', Q2}]) =:= lists:sort(R),
    %% error case
    [] = lmq_queue_mgr:match("AAA"),
    {error, invalid_regexp} = lmq_queue_mgr:match("a[1-").

restart_queue(_Config) ->
    Q1 = lmq_queue_mgr:get(test, [create]),
    exit(Q1, kill),
    timer:sleep(50), % sleep until DOWN message handled
    Q2 = lmq_queue_mgr:get(test),
    true = Q1 =/= Q2.

auto_load(_Config) ->
    DefaultProps = [{"lmq", [{retry, 0}]}],
    lmq_lib:set_lmq_info(default_props, DefaultProps),
    lmq_lib:create(auto_loaded_1),
    lmq_lib:create(auto_loaded_2),
    {ok, _} = lmq_queue_supersup:start_link(),
    timer:sleep(100), % wait until queue will be started
    DefaultProps = lmq_queue_mgr:get_default_props(),
    true = is_pid(lmq_queue_mgr:get('auto_loaded_1')),
    true = is_pid(lmq_queue_mgr:get('auto_loaded_2')),
    not_found = lmq_queue_mgr:get('auto_loaded_3').

default_props(_Config) ->
    PropsList = [{"lmq", [{retry, 0}]}],
    [] = lmq_queue_mgr:get_default_props(),
    ok = lmq_queue_mgr:set_default_props(PropsList),
    {ok, PropsList} = lmq_lib:get_lmq_info(default_props),
    PropsList = lmq_queue_mgr:get_default_props(),
    invalid_syntax = lmq_queue_mgr:set_default_props({}).
