-module(lmq_api_http_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull_ack/1, accidentally_closed/1, keep_abort/1]).

-define(URL_QUEUE(Name), "http://localhost:8280/queues/" ++ Name).
-define(URL_MESSAGE(Name, Id), "http://localhost:8280/messages/" ++ Name ++ "/" ++ Id).
-define(CT_JSON, {"content-type", "application/json"}).

all() ->
    [push_pull_ack, accidentally_closed, keep_abort].

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

push_pull_ack(Config) ->
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
    MsgId = proplists:get_value(<<"id">>, Msg),
    true = is_binary(MsgId),
    <<"normal">> = proplists:get_value(<<"type">>, Msg),
    <<"{\"message\":\"lmq test\"}">> = proplists:get_value(<<"content">>, Msg),

    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId), [], delete).

accidentally_closed(Config) ->
    Name = ?config(qname, Config),
    {error, req_timedout} = ibrowse:send_req(?URL_QUEUE(Name), [], get, [],
        [{inactivity_timeout, 100}]),

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [?CT_JSON], post, "{\"testcase\":\"accidentally_closed\"}"),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"packing\":\"no\"}" = ResBody,

    ct:timetrap(100),
    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    {Msg} = jsonx:decode(list_to_binary(ResBody2)),
    <<"{\"testcase\":\"accidentally_closed\"}">> = proplists:get_value(<<"content">>, Msg).

keep_abort(Config) ->
    Name = ?config(qname, Config),
    Content = "{\"testcase\":\"abort\"}",
    ContentBin = list_to_binary(Content),

    {ok, "200", _, _} = ibrowse:send_req(?URL_QUEUE(Name), [?CT_JSON], post, Content),

    {ok, "200", _, ResBody} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    {Msg} = jsonx:decode(list_to_binary(ResBody)),
    MsgId = proplists:get_value(<<"id">>, Msg),
    ContentBin = proplists:get_value(<<"content">>, Msg),

    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId), [?CT_JSON],
        post, "{\"action\":\"keep\"}"),
    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId), [?CT_JSON],
        post, "{\"action\":\"abort\"}"),

    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId), [?CT_JSON],
        post, "{\"action\":\"abort\"}"),
    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId), [], delete),

    ct:timetrap(100),
    {ok, "200", _, ResBody2} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    {Msg2} = jsonx:decode(list_to_binary(ResBody2)),
    ContentBin = proplists:get_value(<<"content">>, Msg2).
