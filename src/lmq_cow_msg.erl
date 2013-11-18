-module(lmq_cow_msg).

-export([init/3, handle/2, info/3, terminate/3]).

-record(state, {queue, pull, push, ref}).

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
    case validate_timeout(Req) of
        {ok, Timeout, Req2} ->
            Self = self(),
            Ref = make_ref(),
            spawn_link(fun() -> Self ! {Ref, lmq:Pull(Queue, Timeout, Self)} end),
            {loop, Req2, State#state{ref=Ref}};
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
    Res = export_push_resp(case CT of
        undefined -> lmq:Push(Queue, Content);
        _ -> lmq:Push(Queue, [{<<"content-type">>, CT}], Content)
    end),
    Res2 = jsonx:encode(Res),
    {ok, Req4} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/json">>}], Res2, Req3),
    {ok, Req4, State}.

info({Ref, empty}, Req, #state{ref=Ref}=State) ->
    {ok, Req2} = cowboy_req:reply(204, Req),
    {ok, Req2, State};
info({Ref, Msg}, Req, #state{ref=Ref}=State) ->
    {CT, V} = encode_body(proplists:get_value(type, Msg), Msg),
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

export_push_resp({ok, L}) when is_list(L) ->
    {[{N, export_push_resp(R)} || {N, R} <- L]};
export_push_resp(ok) ->
    {[{accum, no}]};
export_push_resp({accum, _}=R) ->
    {[R]}.

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
                {ok, 0.0} -> {ok, 0, Req2};
                {ok, T} -> {ok, T, Req2};
                {error, _} -> {error, Req2}
            end
    end.

encode_body(normal, Msg) ->
    {MD, V} = proplists:get_value(content, Msg),
    CT = proplists:get_value(<<"content-type">>, MD, <<"application/octet-stream">>),
    {CT, V};
encode_body(compound, Msg) ->
    Boundary = proplists:get_value(id, Msg),
    V = to_multipart(Boundary, proplists:get_value(content, Msg)),
    {<<"multipart/mixed; boundary=", Boundary/binary>>, V}.

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
