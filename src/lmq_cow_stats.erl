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
    R = lists:foldr(fun({K, V}, Acc) when K =:= percentile ->
                            [{K, jsonify_proplist_keys(V)}|Acc];
                       ({K, V}, Acc) when K =:= histogram ->
                            [{K, jsonify_histogram(V)}|Acc];
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

jsonify_histogram(L) ->
    lists:foldr(fun({Bin, Count}, Acc) -> [[{bin, Bin}, {count, Count}]|Acc] end, [], L).

%% ==================================================================
%% EUnit test
%% ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

jsonify_stats_test() ->
    Value = [{push,
              [{count,24},
               {one,0.264930464299551},
               {five,0.07182249856427589},
               {fifteen,0.025679351706894803},
               {day,2.7766597276742793e-4},
               {mean,9.008392962075889e-8},
               {acceleration,
                [{one_to_five,6.436932191175838e-4},
                 {five_to_fifteen,7.690524476230181e-5},
                 {one_to_fifteen,2.658345695473958e-4}]}]},
             {pull,
              [{count,24},
               {one,0.264930464299551},
               {five,0.07182249856427589},
               {fifteen,0.025679351706894803},
               {day,2.7766597276742793e-4},
               {mean,9.008394821789985e-8},
               {acceleration,
                [{one_to_five,6.436932191175838e-4},
                 {five_to_fifteen,7.690524476230181e-5},
                 {one_to_fifteen,2.658345695473958e-4}]}]},
             {retention,
              [{min,5.290508270263672e-4},
               {max,0.0031280517578125},
               {arithmetic_mean,0.0015397212084601907},
               {geometric_mean,0.00127043818306925},
               {harmonic_mean,0.0010519247023452565},
               {median,0.0016698837280273438},
               {variance,8.87850095456516e-7},
               {standard_deviation,9.422579771254345e-4},
               {skewness,0.43425944017223067},
               {kurtosis,-1.3902812493309589},
               {percentile,
                [{50,0.0016698837280273438},
                 {75,0.002238035202026367},
                 {90,0.0029451847076416016},
                 {95,0.0031011104583740234},
                 {99,0.0031280517578125},
                 {999,0.0031280517578125}]},
               {histogram,[{0.0031280517578125,17}]},
               {n,17}]}],
    Expected = [{push,
                 [{count,24},
                  {one,0.264930464299551},
                  {five,0.07182249856427589},
                  {fifteen,0.025679351706894803},
                  {day,2.7766597276742793e-4},
                  {mean,9.008392962075889e-8},
                  {acceleration,
                   [{one_to_five,6.436932191175838e-4},
                    {five_to_fifteen,7.690524476230181e-5},
                    {one_to_fifteen,2.658345695473958e-4}]}]},
                {pull,
                 [{count,24},
                  {one,0.264930464299551},
                  {five,0.07182249856427589},
                  {fifteen,0.025679351706894803},
                  {day,2.7766597276742793e-4},
                  {mean,9.008394821789985e-8},
                  {acceleration,
                   [{one_to_five,6.436932191175838e-4},
                    {five_to_fifteen,7.690524476230181e-5},
                    {one_to_fifteen,2.658345695473958e-4}]}]},
                {retention,
                 [{min,5.290508270263672e-4},
                  {max,0.0031280517578125},
                  {arithmetic_mean,0.0015397212084601907},
                  {geometric_mean,0.00127043818306925},
                  {harmonic_mean,0.0010519247023452565},
                  {median,0.0016698837280273438},
                  {variance,8.87850095456516e-7},
                  {standard_deviation,9.422579771254345e-4},
                  {skewness,0.43425944017223067},
                  {kurtosis,-1.3902812493309589},
                  {percentile,
                   [{<<"50">>,0.0016698837280273438},
                    {<<"75">>,0.002238035202026367},
                    {<<"90">>,0.0029451847076416016},
                    {<<"95">>,0.0031011104583740234},
                    {<<"99">>,0.0031280517578125},
                    {<<"999">>,0.0031280517578125}]},
                  {histogram,[[{bin, 0.0031280517578125},{count,17}]]},
                  {n,17}]}],
    ?assertEqual(Expected, jsonify_stats(Value)).

-endif.
