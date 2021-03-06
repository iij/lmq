-module(lmq_hook_invalid).

-export([init/1, hooks/0, activate/1, deactivate/1]).
-export([custom_hook/2]).

init([]) ->
    ok.

hooks() ->
    [custom_hook].

activate([N]) ->
    {ok, N}.

deactivate(N) ->
    true = is_integer(N),
    ok.

custom_hook(N, State) ->
    N + State.
