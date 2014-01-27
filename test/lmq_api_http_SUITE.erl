-module(lmq_api_http_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2, all/0]).
-export([push_pull_ack_delete/1, accidentally_closed/1, nack_ext/1,
    queue_props/1, default_props/1, multi/1, compound/1, error_case/1]).

-define(URL_QUEUE(Name), "http://localhost:9980/messages/" ++ Name).
-define(URL_MULTI(Regexp), "http://localhost:9980/messages?qre=" ++ Regexp).
-define(URL_QUEUE_PROPS(Name), "http://localhost:9980/properties/" ++ Name).
-define(URL_MESSAGE(Name, Id, Reply), "http://localhost:9980/messages/" ++
    Name ++ "/" ++ Id ++ "?reply=" ++ Reply).
-define(URL_QUEUE2(Name), "http://localhost:9980/queues/" ++ Name).
-define(CT_JSON, {"content-type", "application/json"}).
-define(CTE, {<<"content-transfer-encoding">>,<<"binary">>}).

all() ->
    [push_pull_ack_delete, accidentally_closed, nack_ext, queue_props,
     default_props, multi, compound, error_case].

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
    Content = "{\"message\":\"lmq test\"}",
    ResBody = "{\"accum\":\"no\"}",

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [?CT_JSON], post, Content),
    "application/json" = proplists:get_value("content-type", ResHdr),

    {ok, "200", ResHdr2, Content} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    Name = proplists:get_value("x-lmq-queue-name", ResHdr2),
    MsgId = proplists:get_value("x-lmq-message-id", ResHdr2),
    "normal" = proplists:get_value("x-lmq-message-type", ResHdr2),
    true = is_list(MsgId),
    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ack"), [], post),

    %% implicit content-type
    {ok, "200", _, ResBody} = ibrowse:send_req(?URL_QUEUE(Name), [], post, Content),
    {ok, "200", ResHdr3, Content} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/octet-stream" = proplists:get_value("content-type", ResHdr3),

    %% timeout
    {ok, "200", _, ResBody} = ibrowse:send_req(?URL_QUEUE(Name), [], post, Content),
    {ok, "200", _, Content} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?t=0", [], get),
    {ok, "204", _, _} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?t=0", [], get),

    %% ignore cf parameter
    {ok, "200", _, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [?CT_JSON], post, Content),
    {ok, "200", ResHdr4, Content} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?cf=msgpack", [], get),
    "application/json" = proplists:get_value("content-type", ResHdr4),

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE2(Name), [], delete),
    not_found = lmq_queue_mgr:get(list_to_atom(Name)).

accidentally_closed(Config) ->
    Name = ?config(qname, Config),
    Content = "{\"testcase\":\"accidentally_closed\"}",
    {error, req_timedout} = ibrowse:send_req(?URL_QUEUE(Name), [], get, [],
        [{inactivity_timeout, 100}]),

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE(Name),
        [?CT_JSON], post, Content),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"accum\":\"no\"}" = ResBody,

    ct:timetrap(100),
    {ok, "200", ResHdr2, Content} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),

    %% multi
    Content2 = "{\"testcase\":\"accidentally_closed2\"}",
    {error, req_timedout} = ibrowse:send_req(?URL_MULTI(Name), [], get, [],
        [{inactivity_timeout, 10}]),
    {ok, "200", _, _} = ibrowse:send_req(?URL_MULTI(Name),
        [?CT_JSON], post, Content2),

    ct:timetrap(100),
    {ok, "200", _, Content2} = ibrowse:send_req(?URL_MULTI(Name), [], get).

nack_ext(Config) ->
    Name = ?config(qname, Config),
    Content = "{\"testcase\":\"nack_ext\"}",
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [?CT_JSON], patch,
        <<"{\"retry\":1}">>),

    {ok, "200", _, _} = ibrowse:send_req(?URL_QUEUE(Name), [?CT_JSON], post, Content),
    {ok, "200", ResHdr, Content} = ibrowse:send_req(?URL_QUEUE(Name), [], get),
    MsgId = proplists:get_value("x-lmq-message-id", ResHdr),

    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ext"), [], post),
    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "nack"), [], post),

    %% id is changed
    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "nack"), [], post),
    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId, "ack"), [], post),

    {ok, "200", ResHdr2, Content} = ibrowse:send_req(?URL_QUEUE(Name) ++ "?t=0", [], get),
    MsgId2 = proplists:get_value("x-lmq-message-id", ResHdr2),
    {ok, "204", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, MsgId2, "nack"), [], post),
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE(Name) ++ "?t=0", [], get).

queue_props(Config) ->
    Name = ?config(qname, Config),
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [?CT_JSON], patch,
        <<"{\"accum\":30,\"retry\":0}">>),
    {ok, "422", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [?CT_JSON], patch,
        <<"{\"foo\":\"30\"}">>),
    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr),
    "{\"accum\":30,\"retry\":0,\"timeout\":30}" = ResBody,

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], delete),
    {ok, "200", ResHdr2, ResBody2} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),
    "{\"accum\":0,\"retry\":2,\"timeout\":30}" = ResBody2.

default_props(Config) ->
    Name = ?config(qname, Config),
    PropList = "[[\"accum/.*\",{\"accum\":30}],[\".*\",{\"retry\":0}]]",
    {ok, "200", ResHdr, "[]"} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr),

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [?CT_JSON], put,
        PropList),
    {ok, "200", ResHdr2, PropList} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get),
    "application/json" = proplists:get_value("content-type", ResHdr2),

    {ok, "200", _, "{\"accum\":0,\"retry\":0,\"timeout\":30}"} =
        ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], get),

    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], delete),
    {ok, "200", ResHdr, "[]"} = ibrowse:send_req(?URL_QUEUE_PROPS(""), [], get).

multi(_Config) ->
    Names = ["multi%2fa", "multi%2fb"],
    Regexp = "multi%2f.*",
    Content = "{\"testcase\":\"multi\"}",
    ResBody = "{\"multi/a\":{\"accum\":\"no\"},\"multi/b\":{\"accum\":\"no\"}}",

    [{ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], delete)
        || Name <- Names],

    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_MULTI(Regexp),
        [?CT_JSON], post, Content),
    "application/json" = proplists:get_value("content-type", ResHdr),

    {ok, "200", ResHdr2, Content} = ibrowse:send_req(?URL_MULTI(Regexp), [], get),
    {ok, "200", ResHdr3, Content} = ibrowse:send_req(?URL_MULTI(Regexp), [], get),

    "application/json" = proplists:get_value("content-type", ResHdr2),
    "application/json" = proplists:get_value("content-type", ResHdr3),
    Name2 = proplists:get_value("x-lmq-queue-name", ResHdr2),
    Name3 = proplists:get_value("x-lmq-queue-name", ResHdr3),
    MsgId2 = proplists:get_value("x-lmq-message-id", ResHdr2),
    MsgId3 = proplists:get_value("x-lmq-message-id", ResHdr3),
    "normal" = proplists:get_value("x-lmq-message-type", ResHdr2),
    "normal" = proplists:get_value("x-lmq-message-type", ResHdr3),

    ["multi/a", "multi/b"] = lists:sort([Name2, Name3]),
    true = is_list(MsgId2),
    true = is_list(MsgId3),

    %% timeout
    {ok, "200", ResHdr, ResBody} = ibrowse:send_req(?URL_MULTI(Regexp),
        [?CT_JSON], post, Content),
    {ok, "200", _, Content} = ibrowse:send_req(
        ?URL_MULTI(Regexp) ++ "&t=0", [], get),
    {ok, "200", _, Content} = ibrowse:send_req(
        ?URL_MULTI(Regexp) ++ "&t=0", [], get),
    {ok, "204", _, _} = ibrowse:send_req(
        ?URL_MULTI(Regexp) ++ "&t=0", [], get).

compound(Config) ->
    Name = ?config(qname, Config),
    C1 = msgpack:pack({[{"testcase", "compound 1"}]}),
    C2 = <<"{\"testcase\":\"compound 2\"}">>,
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name),
        [?CT_JSON], patch, <<"{\"accum\":0.3,\"retry\":5,\"timeout\":0}">>),

    {ok, "200", _, "{\"accum\":\"new\"}"} = ibrowse:send_req(
        ?URL_QUEUE(Name), [{"content-type", "application/x-msgpack"}], post, C1),
    {ok, "200", _, "{\"accum\":\"yes\"}"} = ibrowse:send_req(
        ?URL_QUEUE(Name), [?CT_JSON], post, C2),

    {ok, "200", ResHdr, Body} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?t=0.3", [], get, [], [{response_format, binary}]),
    Name = proplists:get_value("x-lmq-queue-name", ResHdr),
    MsgId = proplists:get_value("x-lmq-message-id", ResHdr),
    "compound" = proplists:get_value("x-lmq-message-type", ResHdr),
    true = "multipart/mixed; boundary=" ++ MsgId
        =:= proplists:get_value("content-type", ResHdr),

    F0 = cowboy_multipart:parser(list_to_binary(MsgId)),
    {headers, [{<<"content-type">>, <<"application/x-msgpack">>}, ?CTE], F1} = F0(Body),
    {body, C1, F2} = F1(),
    {end_of_part, F3} = F2(),
    {headers, [{<<"content-type">>, <<"application/json">>}, ?CTE], F4} = F3(),
    {body, C2, F5} = F4(),
    {end_of_part, F6} = F5(),
    eof = F6(),

    %% explicit use multipart format
    {ok, "200", ResHdr2, _} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?t=0&cf=multipart", [], get, [], [{response_format, binary}]),
    MsgId2 = proplists:get_value("x-lmq-message-id", ResHdr2),
    true = "multipart/mixed; boundary=" ++ MsgId2
        =:= proplists:get_value("content-type", ResHdr2),

    %% use msgpack format
    {ok, "200", ResHdr3, Body3} = ibrowse:send_req(
        ?URL_QUEUE(Name) ++ "?t=0&cf=msgpack", [], get, [], [{response_format, binary}]),
    "application/x-msgpack" = proplists:get_value("content-type", ResHdr3),
    {ok, [[{[{"content-type", "application/x-msgpack"}]}, C1],
          [{[{"content-type", "application/json"}]}, C2]]}
        = msgpack:unpack(Body3, [{enable_str, true}]),

    %% multi
    {ok, "200", _, Body3} = ibrowse:send_req(?URL_MULTI(Name) ++ "&t=0&cf=msgpack",
        [], get, [], [{response_format, binary}]),

    %% invalid compound format
    {ok, "400", _, _} = ibrowse:send_req(?URL_QUEUE(Name) ++ "?t=0&cf=json", [], get).

error_case(Config) ->
    Name = ?config(qname, Config),
    {ok, "204", _, _} = ibrowse:send_req(?URL_QUEUE_PROPS(Name), [], delete),
    {ok, "404", _, _} = ibrowse:send_req(?URL_MESSAGE(Name, "foo", "ack"), [], post).
