-module(lmq_misc).
-compile(export_all).

unixtime() ->
    {MegaSecs, Secs, MicroSecs} = os:timestamp(),
    MegaSecs * 1000000 + Secs + MicroSecs / 1000000.
