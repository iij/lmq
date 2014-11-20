-module(lmq_cow_stats).

-export([init/3, rest_init/2, allowed_methods/2, content_types_provided/2]).
-export([stats_to_json/2]).

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, []) ->
    {ok, Req, []}.

allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, stats_to_json}
     ], Req, State}.

stats_to_json(Req, State) ->
    Status = lmq:status(),
    Stats = lmq:stats(),
    Queues = lists:foldr(fun({Name, Info}, Acc) ->
                                 S = jsonify_stats(proplists:get_value(Name, Stats)),
                                 Info2 = [{stats, S}|Info],
                                 [{Name, Info2}|Acc]
                         end, [], proplists:get_value(queues, Status)),
    R = lists:keyreplace(queues, 1, Status, {queues, Queues}),
    {jsonx:encode(R), Req, State}.

jsonify_stats(Stats) ->
    R = lists:foldr(fun({K, V}, Acc) when K =:= percentile orelse K =:= histogram ->
                            [{K, jsonify_proplist_keys(V)}|Acc];
                       (E, Acc) ->
                            [E|Acc]
                    end, [], proplists:get_value(retention, Stats)),
    lists:keyreplace(retention, 1, Stats, {retention, R}).

jsonify_proplist_keys(L) ->
    lists:reverse(jsonify_proplist_keys(L, [])).

jsonify_proplist_keys([], Acc) ->
    Acc;
jsonify_proplist_keys([{K, V}|T], Acc) when is_integer(K) ->
    jsonify_proplist_keys(T, [{integer_to_binary(K), V}|Acc]);
jsonify_proplist_keys([E|T], Acc) ->
    jsonify_proplist_keys(T, [E|Acc]).
