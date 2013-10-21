-module(lmq_cow_queue).

-export([init/3, rest_init/2, allowed_methods/2, resource_exists/2, delete_resource/2,
    content_types_provided/2, content_types_accepted/2]).
-export([to_json/2, process_post/2]).

-record(state, {method, name}).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, _Opts) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    {Method, Req3} = cowboy_req:method(Req2),
    {ok, Req3, #state{method=Method,
                      name=binary_to_atom(Name, latin1)}}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>, <<"DELETE">>], Req, State}.

resource_exists(Req, #state{method=Method, name=Name}=State) ->
    case Method of
        <<"DELETE">> ->
            {lmq_queue_mgr:get(Name) =/= not_found, Req, State};
        _ ->
            {true, Req, State}
    end.

delete_resource(Req, #state{name=Name}=State) ->
    ok = lmq:delete(Name),
    {true, Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}
     ], Req, State}.

to_json(Req, #state{method=Method}=State) ->
    to_json(Method, Req, State).

to_json(<<"GET">>, Req, #state{name=Name}=State) ->
    [Socket, Transport] = cowboy_req:get([socket, transport], Req),
    Transport:setopts(Socket, [{active, once}]),
    {_, Closed, Error} = Transport:messages(),

    QPid = lmq_queue_mgr:get(Name, [create]),
    Id = lmq_queue:pull_async(QPid),
    receive
        {Id, Msg} ->
            Resp = [{queue, Name} | lmq_lib:export_message(Msg)],
            {jsonx:encode(Resp), Req, State};
        {Closed, Socket} ->
            {halt, Req, State};
        {Error, Socket, _Reason} ->
            {halt, Req, State}
    end.

process_post(Req, #state{name=Name}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    Packing = case lmq:push(Name, Content) of
        ok -> no;
        packing_started  -> created;
        packed -> appended
    end,
    Resp = jsonx:encode({[{packing, Packing}]}),
    {true, cowboy_req:set_resp_body(Resp, Req2), State}.
