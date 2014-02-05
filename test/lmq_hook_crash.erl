-module(lmq_hook_crash).

-export([init/0, hooks/0, activate/1, deactivate/1]).
-export([hook1/2]).

init() ->
    ok.

hooks() ->
    [hook1, hook2].

activate([N]) ->
    {ok, N}.

deactivate(N) ->
    N / 0.

hook1(N, State) ->
    State / N.
