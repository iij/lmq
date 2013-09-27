-module(lmq_event_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("lmq.hrl").
-include("lmq_test.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0]).
-export([emit_new_message/1, handle_new_message/1, handle_queue_created/1]).

all() ->
    [emit_new_message, handle_new_message, handle_queue_created].

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
    lmq_event:add_handler(lmq_test_handler, self()),
    [{qname, lmq_event_test} | Config].

end_per_testcase(_, Config) ->
    Name = ?config(qname, Config),
    lmq_queue_mgr:delete(Name).

emit_new_message(Config) ->
    Name = ?config(qname, Config),
    Q = lmq_queue_mgr:get(Name, [create]),
    lmq_queue:push(Q, 1),
    ?EVENT_OR_FAIL({local, {new_message, Name}}).

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

handle_queue_created(_Config) ->
    lmq_queue_mgr:get('lmq/mpull/a', [create]),
    lmq_queue_mgr:get('lmq/mpull/b', [create]),
    {ok, Pid} = lmq_mpull:start(),
    Parent = self(), Ref = make_ref(),
    spawn(fun() -> Parent ! {Ref, lmq_mpull:pull(Pid, <<"lmq/mpull/.*">>, 100)} end),
    timer:sleep(10),
    Q3 = lmq_queue_mgr:get('lmq/mpull/c', [create]),
    lmq_queue:push(Q3, <<"push after pull">>),

    receive {Ref, {[{<<"queue">>, <<"lmq/mpull/c">>}, _, _,
                    {<<"content">>, <<"push after pull">>}]}} -> ok
    after 50 -> ct:fail(no_response)
    end.
