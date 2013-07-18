-module(lmq_misc).
-export([unixtime/0, extend/2]).

unixtime() ->
    {MegaSecs, Secs, MicroSecs} = os:timestamp(),
    MegaSecs * 1000000 + Secs + MicroSecs / 1000000.

extend(Override, Base) ->
    Props = lists:foldl(fun({K, _}=T, Acc) ->
        lists:keystore(K, 1, Acc, T)
    end, Base, Override),
    lists:keysort(1, Props).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-define(assertEq(S, Expected),
    try
        ?assertEqual(S, Expected)
    catch _:_ ->
        ?debugFmt("~nexpected: ~p~n", [Expected]),
        ?debugFmt("~ngot: ~p~n", [S]),
        throw(assertion_error)
    end).

unixtime_test() ->
    T = lmq_misc:unixtime(),
    ?assert(is_float(T)),
    ?assertEq(round(T) div 1000000000, 1).

extend_test() ->
    ?assertEq(lmq_misc:extend([{retry, infinity}, {timeout, 5}],
                              [{timeout, 30}, {type, normal}]),
              [{retry, infinity}, {timeout, 5}, {type, normal}]),
    ?assertEq(lmq_misc:extend([], [{timeout, 30}, {type, normal}]),
              [{timeout, 30}, {type, normal}]).

-endif.
