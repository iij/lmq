-module(lmq_mpull_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([client_closed/1]).

all() ->
    [client_closed].

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
    ok.

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
    [{queue, 'mpull/a'}, _, _, {content, 2}] = lmq_mpull:pull(MP2, <<"mpull/.*">>, 1000),
    lmq:delete('mpull/a').
