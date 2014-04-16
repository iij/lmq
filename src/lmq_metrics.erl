-module(lmq_metrics).

-export([create_queue_metrics/1, update_metric/2, update_metric/3,
    get_metric/2, get_metric_name/2]).

-include("lmq.hrl").

%% ==================================================================
%% Public API
%% ==================================================================

create_queue_metrics(Name) when is_atom(Name) ->
    folsom_metrics:new_meter(get_metric_name(Name, push)),
    folsom_metrics:new_meter(get_metric_name(Name, pull)),
    folsom_metrics:new_histogram(get_metric_name(Name, retention),
        slide_uniform, {60, 100}),

    Metrics = [get_metric_name(Name, push),
               get_metric_name(Name, pull),
               get_metric_name(Name, retention)],
    [folsom_metrics:tag_metric(M, Name) || M <- Metrics],
    [folsom_metrics:tag_metric(M, ?LMQ_ALL_METRICS) || M <- Metrics],
    ok.

update_metric(Name, push) when is_atom(Name) ->
    folsom_metrics:notify({get_metric_name(Name, push), 1}),
    statsderl:increment(statsd_name(Name, push), 1, ?STATSD_SAMPLERATE);

update_metric(Name, pull) when is_atom(Name) ->
    folsom_metrics:notify({get_metric_name(Name, pull), 1}),
    statsderl:increment(statsd_name(Name, pull), 1, ?STATSD_SAMPLERATE).

update_metric(Name, retention, Time) when is_atom(Name) ->
    folsom_metrics:notify({get_metric_name(Name, retention), Time}),
    statsderl:timing(statsd_name(Name, retention), Time, ?STATSD_SAMPLERATE).

get_metric(Name, push) when is_atom(Name) ->
    folsom_metrics:get_metric_value(get_metric_name(Name, push));

get_metric(Name, pull) when is_atom(Name) ->
    folsom_metrics:get_metric_value(get_metric_name(Name, pull));

get_metric(Name, retention) when is_atom(Name) ->
    folsom_metrics:get_histogram_statistics(get_metric_name(Name, retention)).

get_metric_name(Name, Type) when is_atom(Name), is_atom(Type) ->
    get_metric_name(atom_to_binary(Name, latin1), Type);

get_metric_name(Name, push) when is_binary(Name) ->
    get_metric_name(Name, <<"push">>);

get_metric_name(Name, pull) when is_binary(Name) ->
    get_metric_name(Name, <<"pull">>);

get_metric_name(Name, retention) when is_binary(Name) ->
    get_metric_name(Name, <<"retention">>);

get_metric_name(Name, Type) when is_binary(Name), is_binary(Type) ->
    <<Name/binary, <<$_>>/binary, Type/binary>>.

%% ==================================================================
%% EUnit tests
%% ==================================================================

statsd_name(Name, Action) ->
    lists:flatten(io_lib:format("lmq.~s.~s", [Name, Action])).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

get_metric_name_test() ->
    ?assertEqual(<<"foo_push">>, get_metric_name(foo, push)),
    ?assertEqual(<<"foo_pull">>, get_metric_name(foo, pull)),
    ?assertEqual(<<"foo_retention">>, get_metric_name(foo, retention)).

statsd_name_test() ->
    ?assertEqual("lmq.queue.push", statsd_name(queue, push)),
    ?assertEqual("lmq.Q/N.push", statsd_name('Q/N', push)).

-endif.
