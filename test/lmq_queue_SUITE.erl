-module(lmq_queue_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, all/0]).
-export([test/1]).

all() ->
    [test].

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

test(_Config) ->
    lmq_queue:start_link(),
    lmq_lib:create(message),
    ok = lmq_queue:push("foo"),
    M1 = lmq_queue:pull(),
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:return(UUID1),
    not_found = lmq_queue:return(UUID1),
    not_found = lmq_queue:complete(UUID1),
    M2 = lmq_queue:pull(),
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:complete(UUID2),
    ok.
