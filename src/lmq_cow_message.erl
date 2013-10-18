-module(lmq_cow_message).

-export([init/3, rest_init/2, allowed_methods/2, allow_missing_post/2,
    resource_exists/2, delete_resource/2,
    content_types_accepted/2]).
-export([process_post/2]).

-record(state, {action}).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Opts) ->
    {ok, Req, #state{}}.

allowed_methods(Req, State) ->
    {[<<"POST">>, <<"DELETE">>], Req, State}.

allow_missing_post(Req, State) ->
    {false, Req, State}.

resource_exists(Req, State) ->
    %% Since no efficient way exists to know whether the message exists
    %% or not, try to delete the message here.
    {Method, Req2} = cowboy_req:method(Req),
    case Method of
        <<"DELETE">> -> ack(Req2, State);
        <<"POST">> -> action(Req2, State);
        _ -> {true, Req2, State}
    end.

delete_resource(Req, State) ->
    {true, Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}
     ], Req, State}.

%% ==================================================================
%% Private functions
%% ==================================================================

process_post(Req, #state{action=ok}=State) ->
    {true, Req, State};
process_post(Req, State) ->
    {false, Req, State}.

ack(Req, State) ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    {MsgId, Req3} = cowboy_req:binding(id, Req2),
    case lmq:ack(Queue, MsgId) of
        ok -> {true, Req3, State};
        {error, _} -> {false, Req3, State}
    end.

action(Req, State) ->
    {ok, Body, Req2} = cowboy_req:body(Req),
    action(jsonx:decode(Body), Req2, State).

action({[{<<"action">>, Action}]}, Req, State) when is_binary(Action) ->
    action(binary_to_existing_atom(Action, latin1), Req, State);
action(Fun, Req, State) when Fun =:= abort ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    {MsgId, Req3} = cowboy_req:binding(id, Req2),
    case lmq:Fun(Queue, MsgId) of
        ok -> {true, Req3, State#state{action=ok}};
        {error, Reason} -> {false, Req3, State#state{action=Reason}}
    end;
action(_, Req, State) ->
    {true, Req, State#state{action=action_not_found}}.
