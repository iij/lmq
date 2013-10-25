-module(lmq_cow_message).

-export([init/3, rest_init/2, malformed_request/2, allowed_methods/2,
    allow_missing_post/2, resource_exists/2, content_types_accepted/2]).
-export([process_post/2]).

-record(state, {reply, action}).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Opts) ->
    {Reply, Req2} = cowboy_req:qs_val(<<"reply">>, Req),
    {ok, Req2, #state{reply=Reply}}.

malformed_request(Req, #state{reply=Reply}=State) ->
    Invalid = false =:= lists:member(Reply, [<<"ack">>, <<"nack">>, <<"ext">>]),
    {Invalid, Req, State}.

allowed_methods(Req, State) ->
    {[<<"POST">>], Req, State}.

allow_missing_post(Req, State) ->
    {false, Req, State}.

resource_exists(Req, State) ->
    %% Since no efficient way exists to know whether the message exists
    %% or not, try to process request here.
    action(Req, State).

content_types_accepted(Req, State) ->
    {[{'*', process_post}], Req, State}.

%% ==================================================================
%% Private functions
%% ==================================================================

process_post(Req, #state{action=ok}=State) ->
    {true, Req, State};
process_post(Req, State) ->
    {false, Req, State}.

action(Req, #state{reply= <<"ack">>}=State) ->
    action(ack, Req, State);
action(Req, #state{reply= <<"nack">>}=State) ->
    action(abort, Req, State);
action(Req, #state{reply= <<"ext">>}=State) ->
    action(keep, Req, State).

action(Fun, Req, State) ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    {MsgId, Req3} = cowboy_req:binding(id, Req2),
    case lmq:Fun(Queue, MsgId) of
        ok -> {true, Req3, State#state{action=ok}};
        {error, Reason} -> {false, Req3, State#state{action=Reason}}
    end.
