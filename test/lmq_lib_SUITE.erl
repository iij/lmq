-module(lmq_lib_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, all/0]).
-export([create/1, complete/1, return/1, reset_timeout/1, error_case/1]).

all() ->
    [create, complete, return, reset_timeout, error_case].

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

init_per_testcase(create, Config) ->
    Config;
init_per_testcase(_, Config) ->
    Name = test,
    ok = lmq_lib:enqueue(Name, make_ref()),
    lmq_lib:create(Name),
    [{qname, Name} | Config].

create(_Config) ->
    ok = lmq_lib:create(test),
    message = mnesia:table_info(test, record_name),
    ok = lmq_lib:create(test).

complete(Config) ->
    Name = ?config(qname, Config),
    M = lmq_lib:dequeue(Name),
    {_, UUID} = M#message.id,
    ok = lmq_lib:complete(Name, UUID),
    not_found = lmq_lib:complete(Name, UUID).

return(Config) ->
    Name = ?config(qname, Config),
    M = lmq_lib:dequeue(Name),
    {_, UUID} = M#message.id,
    ok = lmq_lib:return(Name, UUID),
    not_found = lmq_lib:return(Name, UUID).

reset_timeout(Config) ->
    Name = ?config(qname, Config),
    M = lmq_lib:dequeue(Name),
    {_, UUID} = M#message.id,
    ok = lmq_lib:reset_timeout(Name, UUID),
    not_found = lmq_lib:reset_timeout(Name, "AAA").

error_case(_Config) ->
    Name = '__abcdefg__',
    {error, {no_exists, _}} = lmq_lib:enqueue(Name, make_ref()),
    {error, {no_exists, _}} = lmq_lib:dequeue(Name),
    {error, {no_exists, _}} = lmq_lib:complete(Name, "AAA"),
    {error, {no_exists, _}} = lmq_lib:return(Name, "AAA"),
    {error, {no_exists, _}} = lmq_lib:reset_timeout(Name, "AAA").
