-module(lmq_hook_test).
-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun start/0, fun stop/1, F}).

%% ==================================================================
%% test descriptions
%% ==================================================================
start_stop_test_() ->
    {"The hook manager can be started, stopped and has a registered name",
     ?setup(fun is_registered/1)}.

register_test_() ->
    [{"A hook can be registered and be called",
      ?setup(fun register_hook/1)},
     {"Multiple hooks can be registered and be called sequentially",
      ?setup(fun register_multiple_hooks/1)},
     {"Hooks can be updated",
      ?setup(fun update_hooks/1)},
     {"Hooks cannot be affected other queues",
      ?setup(fun other_queue/1)},
     {"Hooks can be configured separately per queue",
      ?setup(fun configured_per_queue/1)},
     {"Registering never crashes and simply aborts",
      ?setup(fun abort_registering/1)},
     {"Unregistering never crashes",
      ?setup(fun unregistering_never_crash/1)},
     {"Hooks not included in new config are unregistered",
      ?setup(fun automatic_unregister/1)}
    ].

call_test_() ->
    [{"Calling never crashes",
     ?setup(fun call_never_crash/1)}].

%% ==================================================================
%% setup functions
%% ==================================================================
start() ->
    {ok, Pid} = lmq_hook:start_link(),
    Pid.

stop(_) ->
    lmq_hook:stop().

%% ==================================================================
%% actual tests
%% ==================================================================
is_registered(Pid) ->
    [?_assert(erlang:is_process_alive(Pid)),
     ?_assertEqual(Pid, whereis(lmq_hook))].

register_hook(_) ->
    Config = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    Res = lmq_hook:register(hook_test, Config),
    [?_assertEqual(ok, Res),
     ?_assertEqual(3, lmq_hook:call(hook_test, custom_hook, 2))].

register_multiple_hooks(_) ->
    Config = [{custom_hook, [{lmq_hook_sample1, [1]}, {lmq_hook_sample2, [1, 2]}]}],
    Res = lmq_hook:register(hook_test, Config),
    [?_assertEqual(ok, Res),
     ?_assertEqual(6, lmq_hook:call(hook_test, custom_hook, 2))].

update_hooks(_) ->
    Config1 = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    Config2 = [{custom_hook, [{lmq_hook_sample1, [1]}, {lmq_hook_sample2, [1, 2]}]}],
    Config3 = [{custom_hook, [{lmq_hook_sample2, [1, 2]}, {lmq_hook_sample1, [1]}]}],
    Config4 = [{custom_hook, [{lmq_hook_sample2, [1, 2]}]}],
    Res = [lmq_hook:register(hook_test, Config1),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config2),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config3),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config4),
           lmq_hook:call(hook_test, custom_hook, 2)],
    [?_assertEqual([ok, 3, ok, 6, ok, 5, ok, 4], Res)].

other_queue(_) ->
    Config = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    ok = lmq_hook:register(hook_test, Config),
    [?_assertEqual(2, lmq_hook:call(not_hooked, custom_hook, 2))].

configured_per_queue(_) ->
    Config1 = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    Config2 = [{custom_hook, [{lmq_hook_sample1, [2]}]}],
    Config3 = [{custom_hook, [{lmq_hook_sample2, [2, 3]}]}],
    Res = [lmq_hook:register(hook_test1, Config1),
           lmq_hook:register(hook_test2, Config2),
           lmq_hook:register(hook_test3, Config3)],
    [?_assertEqual([ok, ok, ok], Res),
     ?_assertEqual(2, lmq_hook:call(hook_test1, custom_hook, 1)),
     ?_assertEqual(3, lmq_hook:call(hook_test2, custom_hook, 1)),
     ?_assertEqual(6, lmq_hook:call(hook_test3, custom_hook, 1))].

abort_registering(_) ->
    Config1 = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    Config2 = [{custom_hook, [{lmq_hook_sample2, [1]}]}],
    Config3 = [{custom_hook, [{lmq_hook_no_exist, [1]}]}],
    Config4 = [{custom_hook, [{lmq_hook_invalid, [1]}]}],
    Config5 = [{invalid_hook, [{lmq_hook_sample1, [1]}]}],
    Res = [lmq_hook:register(hook_test, Config1),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config2),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config3),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config4),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:register(hook_test, Config5),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:call(hook_test, invalid_hook, 2)],
    [?_assertEqual([ok, 3,
                    {error, bad_config}, 3,
                    {error, bad_hook}, 3,
                    {error, bad_hook}, 3,
                    {error, bad_config}, 3, 2], Res)].

unregistering_never_crash(_) ->
    Config1 = [{hook1, [{lmq_hook_crash, [2]}]}],
    Config2 = [{hook1, []}],
    Res = [lmq_hook:register(hook_test, Config1),
           lmq_hook:register(hook_test, Config2)],
    [?_assertEqual([ok, ok], Res)].

automatic_unregister(_) ->
    Config1 = [{custom_hook, [{lmq_hook_sample1, [1]}]}],
    Config2 = [{custom_hook2, [{lmq_hook_sample2, [1, 2]}]}],
    Res = [lmq_hook:register(hook_test, Config1),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:call(hook_test, custom_hook2, 2),
           lmq_hook:register(hook_test, Config2),
           lmq_hook:call(hook_test, custom_hook, 2),
           lmq_hook:call(hook_test, custom_hook2, 2)],
    [?_assertEqual([ok, 3, 2, ok, 2, 4], Res)].

call_never_crash(_) ->
    Config = [{hook1, [{lmq_hook_crash, [2]}]}],
    ok = lmq_hook:register(hook_test, Config),
    [?_assertEqual(1.0, lmq_hook:call(hook_test, hook1, 2)),
     ?_assertEqual(0, lmq_hook:call(hook_test, hook1, 0)),
     ?_assertEqual(1, lmq_hook:call(hook_test, hook2, 1))].
