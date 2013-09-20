-module(lmq_event_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("lmq.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([handle_new_message/1]).

-define(LMQ_EVENT, lmq_event).

all() ->
    [handle_new_message].

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
    [{qname, lmq_event_test} | Config].

end_per_testcase(_, Config) ->
    Name = ?config(qname, Config),
    lmq_queue_mgr:delete(Name).

handle_new_message(Config) ->
    Name = ?config(qname, Config),
    gen_event:notify(?LMQ_EVENT, {remote, {new_message, Name}}),
    timer:sleep(50),
    not_found = lmq_queue_mgr:get(Name),

    Q = lmq_queue_mgr:get(Name, [create]),
    Parent = self(),
    spawn(fun() -> Parent ! {Q, lmq_queue:pull(Q)} end),
    timer:sleep(50),
    lmq_lib:enqueue(Name, 1),
    gen_event:notify(?LMQ_EVENT, {remote, {new_message, Name}}),
    receive {Q, M} when M#message.content =:= 1 -> ok
    after 50 -> ct:fail(no_response)
    end.
