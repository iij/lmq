-module(lmq_api_http_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull/1, accidentally_closed/1]).

-define(URL_QUEUE(Name), "http://localhost:8280/queues/" ++ Name).

all() ->
    [push_pull, accidentally_closed].

init_per_suite(Config) ->
    Priv = ?config(priv_dir, Config),
    application:start(mnesia),
    application:set_env(mnesia, dir, Priv),
    lmq:start(),
    ibrowse:start(),
    Config.

end_per_suite(_Config) ->
    lmq:stop(),
    mnesia:delete_schema([node()]).

init_per_testcase(_, Config) ->
    [{qname, "http_api_test"} | Config].

end_per_testcase(_, Config) ->
    Name = ?config(qname, Config),
    lmq_queue_mgr:delete(list_to_atom(Name)).

push_pull(Config) ->
    Name = ?config(qname, Config),
    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [{"content-type", "application/json"}],
        post, "{\"message\":\"lmq test\"}"),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"packing\":\"no\"}" = ResBody,

    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    {Msg} = jsonx:decode(list_to_binary(ResBody2)),
    true = list_to_binary(Name) =:= proplists:get_value(<<"queue">>, Msg),
    true = is_binary(proplists:get_value(<<"id">>, Msg)),
    <<"normal">> = proplists:get_value(<<"type">>, Msg),
    <<"{\"message\":\"lmq test\"}">> = proplists:get_value(<<"content">>, Msg).

accidentally_closed(Config) ->
    Name = ?config(qname, Config),
    {error, req_timedout} = ibrowse:send_req(?URL_QUEUE(Name), [], get, [],
        [{inactivity_timeout, 100}]),

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [{"content-type", "application/json"}],
        post, "{\"testcase\":\"accidentally_closed\"}"),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"packing\":\"no\"}" = ResBody,

    ct:timetrap(100),
    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    {Msg} = jsonx:decode(list_to_binary(ResBody2)),
    <<"{\"testcase\":\"accidentally_closed\"}">> = proplists:get_value(<<"content">>, Msg).
