-module(lmq_queue_SUITE).

-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, all/0]).
-export([create/1]).

all() ->
    [create].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:set_env(mnesia, dir, Priv),
    lmq:install([node()]),
    application:start(mnesia),
    application:start(lmq),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    ok.

create(_Config) ->
    ok = lmq_queue:create(test),
    message = mnesia:table_info(test, record_name),
    ok = lmq_queue:create(test).
