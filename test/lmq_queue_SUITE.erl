-module(lmq_queue_SUITE).

-include("lmq.hrl").
-include_lib("common_test/include/ct.hrl").
-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2,
    all/0, groups/0]).
-export([init/1, push_pull_done/1, release/1, release_multi/1, multi_queue/1,
    pull_timeout/1, async_request/1, pull_async/1, pull_and_timeout/1]).

all() ->
    [init, push_pull_done, release, release_multi, multi_queue, pull_timeout,
    async_request, pull_async, {group, timing}].

groups() ->
    [{timing, [{repeat_until_any_fail, 10}], [pull_and_timeout]}].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    application:start(lager),
    application:start(folsom),
    ok = lmq_lib:init_mnesia(),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]).

init_per_testcase(init, Config) ->
    {ok, _} = lmq_event:start_link(),
    Config;

init_per_testcase(_, Config) ->
    {ok, _} = lmq_event:start_link(),
    {ok, Pid} = lmq_queue:start_link(message),
    [{queue, Pid} | Config].

end_per_testcase(init, _Config) ->
    ok;
end_per_testcase(_, Config) ->
    lmq_queue:stop(?config(queue, Config)),
    lmq_lib:delete(message).

init(_Config) ->
    not_found = lmq_lib:queue_info(queue_test_1),
    {ok, Q1} = lmq_queue:start_link(queue_test_1),
    [] = lmq_lib:queue_info(queue_test_1),
    ?DEFAULT_QUEUE_PROPS = lmq_queue:get_properties(Q1),
    lmq_queue:stop(Q1),

    P2 = lmq_misc:extend([{timeout, 10}], ?DEFAULT_QUEUE_PROPS),
    {ok, Q2} = lmq_queue:start_link(queue_test_1, [{timeout, 10}]),
    [{timeout, 10}] = lmq_lib:queue_info(queue_test_1),
    P2 = lmq_queue:get_properties(Q2),
    lmq_queue:stop(Q2),

    {ok, Q3} = lmq_queue:start_link(queue_test_1),
    [{timeout, 10}] = lmq_lib:queue_info(queue_test_1),
    P2 = lmq_queue:get_properties(Q3),
    lmq_queue:stop(Q3).

push_pull_done(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M = lmq_queue:pull(Pid),
    {TS, UUID} = M#message.id,
    true = is_float(TS),
    true = is_binary(UUID),
    uuid:uuid_to_string(UUID),
    Ref = M#message.content,
    ok = lmq_queue:done(Pid, UUID).

release(Config) ->
    Pid = ?config(queue, Config),
    Ref = make_ref(),
    ok = lmq_queue:push(Pid, Ref),
    M1 = lmq_queue:pull(Pid),
    Ref = M1#message.content,
    {_, UUID1} = M1#message.id,
    ok = lmq_queue:release(Pid, UUID1),
    not_found = lmq_queue:release(Pid, UUID1),
    not_found = lmq_queue:done(Pid, UUID1),
    M2 = lmq_queue:pull(Pid),
    Ref = M2#message.content,
    {_, UUID2} = M2#message.id,
    true = UUID1 =/= UUID2,
    ok = lmq_queue:done(Pid, UUID2).

release_multi(Config) ->
    Pid = ?config(queue, Config),
    R = make_ref(),
    Parent = self(),
    ok = lmq_queue:push(Pid, R),
    M1 = lmq_queue:pull(Pid),
    spawn(fun() -> Parent ! lmq_queue:pull(Pid) end),
    R = M1#message.content,
    {_, UUID1} = M1#message.id,
    timer:sleep(10), %% waiting for starting process
    ok = lmq_queue:release(Pid, UUID1),
    receive
        M2 ->
            R = M2#message.content,
            {_, UUID2} = M2#message.id,
            true = UUID1 =/= UUID2,
            ok = lmq_queue:done(Pid, UUID2)
    after 100 ->
        ct:fail(no_response)
    end.

multi_queue(Config) ->
    Q1 = ?config(queue, Config),
    {ok, Q2} = lmq_queue:start_link(for_test),
    Ref1 = make_ref(),
    Ref2 = make_ref(),
    ok = lmq_queue:push(Q1, Ref1),
    ok = lmq_queue:push(Q2, Ref2),
    M2 = lmq_queue:pull(Q2), Ref2 = M2#message.content,
    M1 = lmq_queue:pull(Q1), Ref1 = M1#message.content,
    ok = lmq_queue:done(Q1, element(2, M1#message.id)),
    ok = lmq_queue:retain(Q2, element(2, M2#message.id)),
    ok = lmq_queue:release(Q2, element(2, M2#message.id)),
    M3 = lmq_queue:pull(Q2),
    ok = lmq_queue:done(Q2, element(2, M3#message.id)),
    ok = lmq_queue:stop(Q2).

pull_timeout(_Config) ->
    {ok, Q} = lmq_queue:start_link(pull_timeout, [{timeout, 0.3}]),
    Ref = make_ref(),
    empty = lmq_queue:pull(Q, 0),
    ok = lmq_queue:push(Q, Ref),
    M1 = lmq_queue:pull(Q, 0), Ref = M1#message.content,
    M2 = lmq_queue:pull(Q), Ref = M2#message.content,
    true = M1 =/= M2,
    empty = lmq_queue:pull(Q, 0.2),
    M3 = lmq_queue:pull(Q, 0.2), Ref = M3#message.content.

async_request(_Config) ->
    {ok, Q} = lmq_queue:start_link(async_request, [{timeout, 0.4}]),
    R1 = make_ref(),
    R2 = make_ref(),
    ok = lmq_queue:push(Q, R1),
    ok = lmq_queue:push(Q, R2),
    Parent = self(),
    spawn(fun() ->
        Parent ! {1, lmq_queue:pull(Q)},
        Parent ! {2, lmq_queue:pull(Q)},
        Parent ! {3, lmq_queue:pull(Q, 0.5)}
    end),
    lists:foreach(fun(_) ->
        receive
            {1, M1} -> ct:pal("~p", [M1]), R1 = M1#message.content;
            {2, M2} ->
                ct:pal("~p", [M2]), {_, UUID2} = M2#message.id,
                ok = lmq_queue:done(Q, UUID2);
            {3, M3} -> ct:pal("~p", [M3]), R1 = M3#message.content
        end
    end, lists:seq(1, 3)).

pull_async(_Config) ->
    {ok, Q} = lmq_queue:start_link(message, [{timeout, 0.1}]),
    R = make_ref(),
    lmq_queue:push(Q, R),
    Id1 = lmq_queue:pull_async(Q),
    receive {Id1, M1} when R =:= M1#message.content -> ok
    after 100 -> ct:fail(no_response)
    end,

    Id2 = lmq_queue:pull_async(Q),
    receive {Id2, M2} when R =:= M2#message.content -> ok
    after 150 -> ct:fail(no_response)
    end,

    Id3 = lmq_queue:pull_async(Q),
    ok = lmq_queue:pull_cancel(Q, Id3),
    receive {Id3, _} -> ct:fail(cancel_failed)
    after 150 -> ok
    end.

pull_and_timeout(Config) ->
    Pid = ?config(queue, Config),
    Parent = self(),
    Ref = make_ref(),
    F = fun() -> Parent ! {Ref, lmq_queue:pull(Pid, 0.01)} end,
    [spawn(F) || _ <- lists:seq(1, 100)],
    wait_pull_and_timeout(Ref, 100).

wait_pull_and_timeout(_, 0) ->
    ok;
wait_pull_and_timeout(Ref, N) ->
    receive {Ref, empty} -> wait_pull_and_timeout(Ref, N-1)
    after 200 -> ct:fail(no_response)
    end.
