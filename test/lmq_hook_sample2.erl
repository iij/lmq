-module(lmq_hook_sample2).
-behaviour(lmq_hook).

-export([init/0, hooks/0, activate/1, deactivate/1]).
-export([custom_hook/2]).

init() ->
    ok.

hooks() ->
    [custom_hook].

activate([N, M]) ->
    {ok, N * M}.

deactivate(N) ->
    true = is_integer(N),
    ok.

custom_hook(N, State) ->
    N * State.
