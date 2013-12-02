-module(lmq_mpull_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([pull/1, pull_async/1, client_closed/1]).

all() ->
    [pull, pull_async, client_closed].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    lmq:start(),
    Config.

end_per_suite(_Config) ->
    lmq:stop(),
    mnesia:delete_schema([node()]).

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, _Config) ->
    Queues = ['mpull/a', 'mpull/b'],
    [lmq:delete(Q) || Q <- Queues],
    ok.

pull(_Config) ->
    Queues = ['mpull/a', 'mpull/b'],
    [lmq:update_props(Q, [{retry, 0}]) || Q <- Queues],
    [lmq:push(Q, Q) || Q <- Queues],

    Pids = [Pid || {ok, Pid} <- [lmq_mpull:start() || _ <- lists:seq(1, 4)]],
    [{queue, R1}, _, _, _] = lmq_mpull:pull(lists:nth(1, Pids), <<"mpull/.*">>),
    [{queue, R2}, _, _, _] = lmq_mpull:pull(lists:nth(2, Pids), <<"mpull/.*">>, 0),
    true = lists:sort([R1, R2]) =:= Queues,

    empty = lmq_mpull:pull(lists:nth(3, Pids), <<"mpull/.*">>, 0),
    empty = lmq_mpull:pull(lists:nth(4, Pids), <<"mpull/.*">>, 200).

pull_async(_Config) ->
    lmq:push('mpull/a', 1),
    {ok, MP1} = lmq_mpull:start(),
    {ok, Ref1} = lmq_mpull:pull_async(MP1, <<"mpull/a">>),
    receive {Ref1, [{queue, 'mpull/a'}, _, _, {content, {[], 1}}]} -> ok
    after 50 -> ct:fail(no_response)
    end,

    {ok, MP2} = lmq_mpull:start(),
    {ok, _} = lmq_mpull:pull_async(MP2, <<"mpull/a">>),
    ok = lmq_mpull:pull_cancel(MP2),

    lmq:push('mpull/a', 3),
    {ok, MP3} = lmq_mpull:start(),
    {ok, Ref3} = lmq_mpull:pull_async(MP3, <<"mpull/a">>),
    receive {Ref3, [{queue, 'mpull/a'}, _, _, {content, {[], 3}}]} -> ok
    after 50 -> ct:fail(no_response)
    end.

client_closed(_Config) ->
    lmq:push('mpull/a', 1),
    lmq:pull('mpull/a', 0),
    Pid = spawn(fun() ->
        {ok, MP1} = lmq_mpull:start(),
        lmq_mpull:pull(MP1, <<"mpull/.*">>, 1000)
    end),
    timer:sleep(10),
    exit(Pid, kill),
    timer:sleep(10),

    lmq:push('mpull/a', 2),
    {ok, MP2} = lmq_mpull:start(),
    [{queue, 'mpull/a'}, _, _, {content, {[], 2}}] = lmq_mpull:pull(MP2, <<"mpull/.*">>, 1000).
