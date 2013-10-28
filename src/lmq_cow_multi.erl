-module(lmq_cow_multi).

-export([init/3, info/3, terminate/3]).
-export([rest_init/2, allowed_methods/2, malformed_request/2,
    content_types_provided/2, content_types_accepted/2]).
-export([process_post/2]).

-record(state, {qre, ref}).

init(_Transport, Req, []) ->
    io:format("connection accepted ~p~n", [self()]),
    case cowboy_req:method(Req) of
        {<<"GET">>, Req2} -> loop_init(Req2);
        _ -> {upgrade, protocol, cowboy_rest}
    end.

loop_init(Req) ->
    case malformed_request(Req, #state{}) of
        {false, Req2, #state{qre=QRE}=State} ->
            Self = self(),
            Ref = make_ref(),
            spawn_link(fun() -> Self ! {Ref, lmq:pull_any(QRE, infinity, Self)} end),
            {loop, Req2, State#state{ref=Ref}};
        {true, Req2, State} ->
            {ok, Req3} = cowboy_req:reply(400, Req2),
            {shutdown, Req3, State}
    end.

%% ==================================================================
%% cowboy loop handler callbacks
%% ==================================================================

info({Ref, Msg}, Req, #state{ref=Ref}=State) ->
    Headers = [{<<"content-type">>, <<"application/json">>}],
    {ok, Req2} = cowboy_req:reply(200, Headers, jsonx:encode(Msg), Req),
    {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
    io:format("connection closed ~p~n", [self()]),
    ok.

%% ==================================================================
%% cowboy rest handler callbacks
%% ==================================================================

rest_init(Req, []) ->
    {ok, Req, #state{}}.

allowed_methods(Req, State) ->
    {[<<"POST">>], Req, State}.

malformed_request(Req, State) ->
    case cowboy_req:qs_val(<<"qre">>, Req) of
        {undefined, Req2} ->
            {true, Req2, State};
        {Regexp, Req2} ->
            case re:compile(Regexp) of
                {ok, _} -> {false, Req2, State#state{qre=Regexp}};
                _ -> {true, Req2, State}
            end
    end.

%% This function is needed even if response has no content.
content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}], Req, State}.

%% ==================================================================
%% public functions
%% ==================================================================

process_post(Req, #state{qre=Regexp}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    case lmq:push_all(Regexp, Content) of
        ok -> {true, Req2, State};
        {error, _Reason} -> {false, Req2, State}
    end.
