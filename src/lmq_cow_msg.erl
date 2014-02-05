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
    {CT, V} = encode_body(proplists:get_value(type, Msg), CF, Msg),
    {ok, Req2} = cowboy_req:reply(200,
        [{<<"content-type">>, CT},
         {<<"x-lmq-queue-name">>, atom_to_binary(
            proplists:get_value(queue, Msg), latin1)},
         {<<"x-lmq-message-id">>, proplists:get_value(id, Msg)},
         {<<"x-lmq-message-type">>, atom_to_binary(
            proplists:get_value(type, Msg), latin1)}
        ], V, Req),
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
    {[{N, export_push_resp(R)} || {N, R} <- L]};
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
    CT = proplists:get_value(<<"content-type">>, MD, <<"application/octet-stream">>),
    {CT, V};
encode_body(compound, multipart, Msg) ->
    Boundary = proplists:get_value(id, Msg),
    V = to_multipart(Boundary, proplists:get_value(content, Msg)),
    {<<"multipart/mixed; boundary=", Boundary/binary>>, V};
encode_body(compound, msgpack, Msg) ->
    V = [[{stringify_metadata(MD)}, V] || {MD, V} <- proplists:get_value(content, Msg)],
    {<<"application/x-msgpack">>, msgpack:pack(V, [{enable_str, true}])}.

to_multipart(Boundary, Contents) when is_list(Contents) ->
    [[[<<"\r\n--">>, Boundary, <<"\r\n">>, encode_multipart_item(C)]
       || C <- Contents],
     <<"\r\n--">>, Boundary, <<"--\r\n">>].

encode_multipart_item({MD, V}) ->
    [<<"Content-Type: ">>,
     proplists:get_value(<<"content-type">>, MD, <<"application/octet-stream">>),
     <<"\r\n">>,
     <<"Content-Transfer-Encoding: binary\r\n">>,
     <<"\r\n">>, V].

stringify_metadata(MD) ->
    stringify_metadata(MD, []).

stringify_metadata([{K, V}|Tail], Acc) when is_binary(K), is_binary(V) ->
    stringify_metadata(Tail, [{binary_to_list(K), binary_to_list(V)}|Acc]);
stringify_metadata([], Acc) ->
    lists:reverse(Acc).
