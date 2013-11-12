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
    Self = self(),
    Ref = make_ref(),
    spawn_link(fun() -> Self ! {Ref, lmq:Pull(Queue, infinity, Self)} end),
    {loop, Req, State#state{ref=Ref}};
init({<<"POST">>, Req}, State) ->
    {ok, Req, State};
init({_, Req}, State) ->
    {ok, Req2} = cowboy_req:reply(405, Req),
    {shutdown, Req2, State}.

handle(Req, #state{queue=Queue, push=Push}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    Res = export_push_resp(lmq:Push(Queue, Content)),
    Res2 = jsonx:encode(Res),
    {ok, Req3} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/json">>}], Res2, Req2),
    {ok, Req3, State}.

info({Ref, Msg}, Req, #state{ref=Ref}=State) ->
    {ok, Req2} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/octet-stream">>},
         {<<"x-lmq-queue-name">>, atom_to_binary(
            proplists:get_value(queue, Msg), latin1)},
         {<<"x-lmq-message-id">>, proplists:get_value(id, Msg)},
         {<<"x-lmq-message-type">>, atom_to_binary(
            proplists:get_value(type, Msg), latin1)}
        ], proplists:get_value(content, Msg), Req),
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
    {[{packed, no}]};
export_push_resp(packing_started) ->
    {[{packed, new}]};
export_push_resp(packed) ->
    {[{packed, yes}]}.

validate_multi_request(Req) ->
    case cowboy_req:qs_val(<<"qre">>, Req) of
        {undefined, Req2} -> {error, Req2};
        {Regexp, Req2} ->
            case re:compile(Regexp) of
                {ok, _} -> {{ok, Regexp}, Req2};
                _ -> {error, Req2}
            end
    end.
