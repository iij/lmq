-module(lmq_cow_message).

-export([init/3, allowed_methods/2, resource_exists/2, delete_resource/2]).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

allowed_methods(Req, State) ->
    {[<<"DELETE">>], Req, State}.

resource_exists(Req, State) ->
    %% Since no efficient way exists to know whether the message exists
    %% or not, try to delete the message here.
    {Method, Req2} = cowboy_req:method(Req),
    case Method of
        <<"DELETE">> -> ack(Req2, State);
        _ -> {true, Req2, State}
    end.

delete_resource(Req, State) ->
    {true, Req, State}.

%% ==================================================================
%% Private functions
%% ==================================================================

ack(Req, State) ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    {MsgId, Req3} = cowboy_req:binding(id, Req2),
    case lmq:ack(Queue, MsgId) of
        ok -> {true, Req3, State};
        {error, _} -> {false, Req3, State}
    end.
