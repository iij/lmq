-module(lmq_cow_msg).

-export([init/3, handle/2, info/3, terminate/3]).
-export([export_push_resp/1]).

-record(state, {name, ref}).

init(_Transport, Req, _Opts) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    init(cowboy_req:method(Req2), #state{name=Name}).

init({<<"GET">>, Req}, #state{name=Name}=State) ->
    Self = self(),
    Ref = make_ref(),
    spawn_link(fun() -> Self ! {Ref, lmq:pull(Name, infinity, Self)} end),
    {loop, Req, State#state{ref=Ref}};
init({<<"POST">>, Req}, State) ->
    {ok, Req, State};
init({_, Req}, State) ->
    {ok, Req2} = cowboy_req:reply(405, Req),
    {shutdown, Req2, State}.

handle(Req, #state{name=Name}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    Res = export_push_resp(lmq:push(Name, Content)),
    Res2 = jsonx:encode(Res),
    {ok, Req3} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/json">>}], Res2, Req2),
    {ok, Req3, State}.

info({Ref, Msg}, Req, #state{name=Name, ref=Ref}=State) ->
    {ok, Req2} = cowboy_req:reply(200,
        [{<<"content-type">>, <<"application/octet-stream">>},
         {<<"x-lmq-queue-name">>, Name},
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
%% Public functions
%% ==================================================================

export_push_resp(ok) ->
    {[{packed, no}]};
export_push_resp(packing_started) ->
    {[{packed, new}]};
export_push_resp(packed) ->
    {[{packed, yes}]}.
