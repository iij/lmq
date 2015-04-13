-module(lmq_cow_msg).

-export([init/3, handle/2, info/3, terminate/3]).

-record(state, {queue, pull, push, ref, cf}).

init(_Transport, Req, []) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    init(cowboy_req:method(Req2), #state{queue=Name, pull=pull, push=push});
init(_Transport, Req, [multi]) ->
    case validate_multi_request(Req) of
        {{ok, Regexp}, Req2} ->
            init(cowboy_req:method(Req2), #state{queue=Regexp, pull=pull_any, push=push_all});
        {error, Req2} ->
            {ok, Req3} = cowboy_req:reply(400, Req2),
            {shutdown, Req3, #state{}}
    end.

init({<<"GET">>, Req}, #state{queue=Queue, pull=Pull}=State) ->
    case validate([fun validate_timeout/1,
                   fun validate_compound_format/1], Req) of
        {ok, [Timeout, CF], Req2} ->
            Self = self(),
            Ref = make_ref(),
            spawn_link(fun() -> Self ! {Ref, lmq:Pull(Queue, Timeout, Self)} end),
            {loop, Req2, State#state{ref=Ref, cf=CF}};
        {error, Req2} ->
            {ok, Req3} = cowboy_req:reply(400, Req2),
            {shutdown, Req3, State}
    end;
init({<<"POST">>, Req}, State) ->
    {ok, Req, State};
init({_, Req}, State) ->
    {ok, Req2} = cowboy_req:reply(405, Req),
    {shutdown, Req2, State}.

handle(Req, #state{queue=Queue, push=Push}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    {CT, Req3} = cowboy_req:header(<<"content-type">>, Req2),
    MD = case CT of
             undefined -> [];
             _ -> [{<<"content-type">>, CT}]
         end,
    Res = export_push_resp(do_push(Push, Queue, MD, Content, Req3)),
    Res2 = jsonx:encode(Res),
    {ok, Req4} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/json">>}], Res2, Req3),
    {ok, Req4, State}.

info({Ref, empty}, Req, #state{ref=Ref}=State) ->
    {ok, Req2} = cowboy_req:reply(204, Req),
    {ok, Req2, State};
info({Ref, Msg}, Req, #state{ref=Ref, cf=CF}=State) ->
    {Hdrs, V} = encode_body(proplists:get_value(type, Msg), CF, Msg),
    Hdrs2 = Hdrs ++ [{<<"x-lmq-queue-name">>,
                      atom_to_binary(proplists:get_value(queue, Msg), latin1)},
                     {<<"x-lmq-message-id">>, proplists:get_value(id, Msg)},
                     {<<"x-lmq-message-type">>,
                      atom_to_binary(proplists:get_value(type, Msg), latin1)},
                     {<<"x-lmq-retry-remaining">>, integer_to_binary(proplists:get_value(retry, Msg))}],
    {ok, Req2} = cowboy_req:reply(200, Hdrs2, V, Req),
    {ok, Req2, State};
info(_Msg, Req, State) ->
    {loop, Req, State}.

terminate({normal, _}, _Req, _State) ->
    %% maybe reuse connection
    ok;
terminate({error, _}, _Req, _State) ->
    %% close connection and halt this process
    error.

%% ==================================================================
%% Private functions
%% ==================================================================
do_push(push, Queue, MD, Content, Req) when is_binary(Queue) ->
    do_push(push, binary_to_atom(Queue, latin1), MD, Content, Req);
do_push(push, Queue, MD, Content, Req) ->
    {MD2, Content2, _} = lmq_hook:call(Queue, pre_http_push, {MD, Content, Req}),
    lmq:push(Queue, MD2, Content2);
do_push(push_all, Regexp, MD, Content, Req) ->
    case lmq_queue_mgr:match(Regexp) of
        {error, _}=R ->
            R;
        Queues ->
            {ok, [{Name, do_push(push, Name, MD, Content, Req)} || {Name, _} <- Queues]}
    end.

export_push_resp({ok, L}) when is_list(L) ->
    L2 = lists:filtermap(fun({N, R}) ->
                            case R of
                                {error, _} -> false;
                                _ -> {true, {N, export_push_resp(R)}}
                            end
                    end, L),
    {L2};
export_push_resp(ok) ->
    {[{accum, no}]};
export_push_resp({accum, _}=R) ->
    {[R]}.

validate(L, Req) when is_list(L) ->
    lists:foldl(fun(F, {ok, Acc, Req2}) ->
        case F(Req2) of
            {ok, V, Req3} -> {ok, Acc ++ [V], Req3};
            {error, Req3} -> {error, Req3}
        end;
    (_, {error, Req2}) ->
        {error, Req2}
    end, {ok, [], Req}, L).

validate_multi_request(Req) ->
    case cowboy_req:qs_val(<<"qre">>, Req) of
        {undefined, Req2} -> {error, Req2};
        {Regexp, Req2} ->
            case re:compile(Regexp) of
                {ok, _} -> {{ok, Regexp}, Req2};
                _ -> {error, Req2}
            end
    end.

validate_timeout(Req) ->
    case cowboy_req:qs_val(<<"t">>, Req) of
        {undefined, Req2} ->
            {ok, infinity, Req2};
        {V, Req2} ->
            case lmq_misc:btof(V) of
                {ok, 0.0} ->
                    {ok, 0, Req2};
                {ok, T} ->
                    case cowboy_req:qs_val(<<"qre">>, Req2) of
                        {undefined, Req3} -> {ok, T, Req3};
                        {_, Req3} -> {ok, round(T * 1000), Req3}
                    end;
                {error, _} ->
                    {error, Req2}
            end
    end.

validate_compound_format(Req) ->
    case cowboy_req:qs_val(<<"cf">>, Req) of
        {undefined, Req2} ->
            {ok, multipart, Req2};
        {<<"multipart">>, Req2} ->
            {ok, multipart, Req2};
        {<<"msgpack">>, Req2} ->
            {ok, msgpack, Req2};
        {_, Req2} ->
            {error, Req2}
    end.

encode_body(normal, _, Msg) ->
    {MD, V} = proplists:get_value(content, Msg),
    {make_headers(MD), V};
encode_body(compound, multipart, Msg) ->
    Boundary = proplists:get_value(id, Msg),
    Hdrs = [{<<"content-type">>, <<"multipart/mixed; boundary=", Boundary/binary>>}],
    V = to_multipart(Boundary, proplists:get_value(content, Msg)),
    {Hdrs, V};
encode_body(compound, msgpack, Msg) ->
    Hdrs = [{<<"content-type">>, <<"application/x-msgpack">>}],
    V = [[{stringify_metadata(make_headers(MD))}, V] || {MD, V} <- proplists:get_value(content, Msg)],
    {Hdrs, msgpack:pack(V, [{enable_str, true}])}.

make_headers(MD) ->
    case proplists:is_defined(<<"content-type">>, MD) of
        true -> MD;
        false -> [{<<"content-type">>, <<"application/octet-stream">>}|MD]
    end.

to_multipart(Boundary, Contents) when is_list(Contents) ->
    [[[<<"\r\n--">>, Boundary, <<"\r\n">>, encode_multipart_item(C)]
       || C <- Contents],
     <<"\r\n--">>, Boundary, <<"--\r\n">>].

encode_multipart_item({MD, V}) ->
    Hdrs = make_headers(MD),
    [[[Key, <<": ">>, Value, <<"\r\n">>] || {Key, Value} <- Hdrs],
     <<"content-transfer-encoding: binary\r\n">>,
     <<"\r\n">>, V].

stringify_metadata(MD) ->
    stringify_metadata(MD, []).

stringify_metadata([{K, V}|Tail], Acc) when is_binary(K), is_binary(V) ->
    stringify_metadata(Tail, [{binary_to_list(K), binary_to_list(V)}|Acc]);
stringify_metadata([], Acc) ->
    lists:reverse(Acc).

%% ==================================================================
%% EUnit test
%% ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

export_push_resp_test_() ->
    [?_assertEqual({[{accum, no}]}, export_push_resp(ok)),
     ?_assertEqual({[{foo, {[{accum, no}]}}, {bar, {[{accum, no}]}}]},
                   export_push_resp({ok, [{foo, ok}, {bar, ok}]})),
     ?_assertEqual({[{bar, {[{accum, no}]}}]},
                   export_push_resp({ok, [{foo, {error, no_queue_exists}}, {bar, ok}]}))].

encode_body_normal_test_() ->
    Msg1 = [{id, <<"id1">>}, {content, {[{<<"content-type">>, <<"text/plain">>}], <<"msg1">>}}],
    Msg2 = [{id, <<"id2">>}, {content, {[], <<"msg2">>}}],
    Msg3 = [{id, <<"id3">>}, {content, {[{<<"x-lmq-sequence">>, <<"1">>}], <<"msg3">>}}],
    [?_assertEqual({[{<<"content-type">>, <<"text/plain">>}], <<"msg1">>},
                   encode_body(normal, multipart, Msg1)),
     ?_assertEqual({[{<<"content-type">>, <<"application/octet-stream">>}], <<"msg2">>},
                   encode_body(normal, multipart, Msg2)),
     ?_assertEqual({[{<<"content-type">>, <<"application/octet-stream">>},
                     {<<"x-lmq-sequence">>, <<"1">>}], <<"msg3">>},
                   encode_body(normal, multipart, Msg3))].

encode_body_multipart_test_() ->
    Msg1 = [{id, <<"id1">>}, {content, [{[{<<"content-type">>, <<"text/plain">>}], <<"msg1">>},
                                        {[], <<"msg2">>},
                                        {[{<<"x-lmq-sequence">>, <<"1">>}], <<"msg3">>}]}],
    [?_assertEqual([{<<"content-type">>, <<"multipart/mixed; boundary=id1">>}],
                   element(1, encode_body(compound, multipart, Msg1))),
     ?_assertEqual(<<"\r\n--id1\r\n",
                     "content-type: text/plain\r\n",
                     "content-transfer-encoding: binary\r\n",
                     "\r\n",
                     "msg1"
                     "\r\n--id1\r\n",
                     "content-type: application/octet-stream\r\n",
                     "content-transfer-encoding: binary\r\n",
                     "\r\n",
                     "msg2",
                     "\r\n--id1\r\n",
                     "content-type: application/octet-stream\r\n",
                     "x-lmq-sequence: 1\r\n",
                     "content-transfer-encoding: binary\r\n",
                     "\r\n",
                     "msg3",
                     "\r\n--id1--\r\n">>,
                   iolist_to_binary(element(2, encode_body(compound, multipart, Msg1))))
    ].

encode_body_msgpack_test_() ->
    Msg1 = [{id, <<"id1">>}, {content, [{[{<<"content-type">>, <<"text/plain">>}], <<"msg1">>},
                                        {[], <<"msg2">>},
                                        {[{<<"x-lmq-sequence">>, <<"1">>}], <<"msg3">>}]}],
    Bin1 = msgpack:pack([[{[{"content-type", "text/plain"}]}, <<"msg1">>],
                         [{[{"content-type", "application/octet-stream"}]}, <<"msg2">>],
                         [{[{"content-type", "application/octet-stream"},
                            {"x-lmq-sequence", "1"}]}, <<"msg3">>]],
                        [{enable_str, true}]),
    [?_assertEqual({[{<<"content-type">>, <<"application/x-msgpack">>}], Bin1},
                   encode_body(compound, msgpack, Msg1))].

-endif.
