-module(lmq_misc).
-compile(export_all).

unixtime() ->
    {MegaSecs, Secs, MicroSecs} = os:timestamp(),
    MegaSecs * 1000000 + Secs + MicroSecs / 1000000.


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

unixtime_test() ->
    T = lmq_misc:unixtime(),
    ?assert(is_float(T)),
    ?assertEqual(round(T) div 1000000000, 1).

-endif.
