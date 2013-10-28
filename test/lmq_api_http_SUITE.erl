-module(lmq_api_http_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull_ack_delete/1, accidentally_closed/1, keep_abort/1,
    queue_props/1, default_props/1, multi/1]).

-define(URL_QUEUE(Name), "http://localhost:8280/msgs/" ++ Name).
-define(URL_MULTI(Regexp), "http://localhost:8280/msgs?qre=" ++ Regexp).
-define(URL_QUEUE_PROPS(Name), "http://localhost:8280/props/" ++ Name).
-define(URL_MESSAGE(Name, Id, Reply), "http://localhost:8280/msgs/" ++
    Name ++ "/" ++ binary_to_list(Id) ++ "?reply=" ++ Reply).
-define(URL_QUEUE2(Name), "http://localhost:8280/queues/" ++ Name).
-define(CT_JSON, {"content-type", "application/json"}).

all() ->
    [push_pull_ack_delete, accidentally_closed, keep_abort, queue_props,
     default_props, multi].

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

push_pull_ack_delete(Config) ->
    Name = ?config(qname, Config),
    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [?CT_JSON], post, "{\"message\":\"lmq test\"}"),
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

    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ack"), [], post),
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE2(Name), [], delete),
    not_found = lmq_queue_mgr:get(list_to_atom(Name)).

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
    <<"{\"testcase\":\"accidentally_closed\"}">> = proplists:get_value(<<"content">>, Msg),

    %% multi
    {error, req_timedout} = ibrowse:send_req(?URL_MULTI(Name), [], get, [],
        [{inactivity_timeout, 10}]),
    {ok, "200", _, _} = ibrowse:send_req(?URL_MULTI(Name),
        [?CT_JSON], post, "{\"testcase\":\"accidentally_closed2\"}"),

    ct:timetrap(100),
    {ok, "200", _, ResBody3} = ibrowse:send_req(?URL_MULTI(Name), [], get),
    {Msg3} = jsonx:decode(list_to_binary(ResBody3)),
    <<"{\"testcase\":\"accidentally_closed2\"}">> = proplists:get_value(<<"content">>, Msg3).

keep_abort(Config) ->
    Name = ?config(qname, Config),
    Content = "{\"testcase\":\"abort\"}",
    ContentBin = list_to_binary(Content),

    {ok, "200", _, _} = ibrowse:send_req(?URL_QUEUE(Name), [?CT_JSON], post, Content),

    {ok, "200", _, ResBody} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    {Msg} = jsonx:decode(list_to_binary(ResBody)),
    MsgId = proplists:get_value(<<"id">>, Msg),
    ContentBin = proplists:get_value(<<"content">>, Msg),

    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ext"), [], post),
    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "nack"), [], post),

    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "nack"), [], post),
    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ack"), [], post),

    ct:timetrap(100),
    {ok, "200", _, ResBody2} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    {Msg2} = jsonx:decode(list_to_binary(ResBody2)),
    ContentBin = proplists:get_value(<<"content">>, Msg2).

queue_props(Config) ->
    Name = ?config(qname, Config),
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [?CT_JSON], put,
        <<"{\"pack\":30,\"retry\":0}">>),
    {ok, "422", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [?CT_JSON], put,
        <<"{\"foo\":\"30\"}">>),
    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"pack\":30,\"retry\":0,\"timeout\":30}" = ResBody,

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], delete),
    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    "{\"pack\":0,\"retry\":2,\"timeout\":30}" = ResBody2.

default_props(Config) ->
    Name = ?config(qname, Config),
    PropList = "[[\"pack/.*\",{\"pack\":30}],[\".*\",{\"retry\":0}]]",
    {ok, "200", ResHdr, "[]"} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr),

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [?CT_JSON], put,
        PropList),
    {ok, "200", ResHdr2, PropList} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),

    {ok, "200", _, "{\"pack\":0,\"retry\":0,\"timeout\":30}"} =
        ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], delete),
    {ok, "200", ResHdr, "[]"} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get).

multi(_Config) ->
    Names = ["multi%2fa", "multi%2fb"],
    Regexp = "multi%2f.*",
    Content = <<"{\"testcase\":\"multi\"}">>,
    [{ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], delete)
        || Name <- Names],

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_MULTI(Regexp),
        [?CT_JSON], post, Content),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"multi/a\":{\"packing\":\"no\"},\"multi/b\":{\"packing\":\"no\"}}" = ResBody,

    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_MULTI(Regexp), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    {ok, "200", ResHdr3, ResBody3} = ibrowse:send_req(?URL_MULTI(Regexp), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr3),

    {Msg} = jsonx:decode(list_to_binary(ResBody2)),
    {Msg2} = jsonx:decode(list_to_binary(ResBody3)),
    Content = proplists:get_value(<<"content">>, Msg),
    Content = proplists:get_value(<<"content">>, Msg2),
    [<<"multi/a">>, <<"multi/b">>] = lists:sort([proplists:get_value(<<"queue">>, Msg),
                                                 proplists:get_value(<<"queue">>, Msg2)]).
