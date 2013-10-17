-module(lmq_cow_queue).

-export([init/3, allowed_methods/2, content_types_provided/2,
    content_types_accepted/2]).
-export([to_json/2, process_post/2]).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}
     ], Req, State}.

to_json(Req, State) ->
    handle(cowboy_req:method(Req), State).

handle({<<"GET">>, Req}, State) ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    Resp = lmq:pull(binary_to_atom(Queue, latin1)),
    {jsonx:encode(Resp), Req2, State}.

process_post(Req, State) ->
    {Queue, Req2} = cowboy_req:binding(name, Req),
    {ok, Content, Req3} = cowboy_req:body(Req2),
    Packing = case lmq:push(binary_to_atom(Queue, latin1), Content) of
        ok -> no;
        packing_started  -> created;
        packed -> appended
    end,
    Resp = jsonx:encode({[{packing, Packing}]}),
    {true, cowboy_req:set_resp_body(Resp, Req3), State}.
