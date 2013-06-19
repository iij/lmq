-module(lmq_misc_test).

-include_lib("eunit/include/eunit.hrl").

unixtime_test() ->
    T = lmq_misc:unixtime(),
    ?assert(is_float(T)),
    ?assertEqual(round(T) div 1000000000, 1).
