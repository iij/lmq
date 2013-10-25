-module(lmq_cow_queue).

-export([init/3, rest_init/2, allowed_methods/2, resource_exists/2, delete_resource/2,
    content_types_provided/2, content_types_accepted/2]).
-export([to_json/2, process_post/2, update_props/2]).

-record(state, {method, name, type=undefined}).

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, []) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    {Method, Req3} = cowboy_req:method(Req2),
    {ok, Req3, #state{method=Method,
                      name=binary_to_atom(Name, latin1)}};
rest_init(Req, [Type]) ->
    {ok, Req2, State} = rest_init(Req, []),
    {ok, Req2, State#state{type=Type}}.

allowed_methods(Req, #state{type=undefined}=State) ->
    {[<<"GET">>, <<"POST">>, <<"DELETE">>], Req, State};
allowed_methods(Req, #state{type=props}=State) ->
    {[<<"GET">>, <<"PUT">>, <<"DELETE">>], Req, State}.

resource_exists(Req, #state{method=Method, name=Name, type=undefined}=State) ->
    case Method of
        <<"DELETE">> ->
            {lmq_queue_mgr:get(Name) =/= not_found, Req, State};
        _ ->
            {true, Req, State}
    end;
resource_exists(Req, State) ->
    {true, Req, State}.

delete_resource(Req, #state{name=Name, type=undefined}=State) ->
    ok = lmq:delete(Name),
    {true, Req, State};
delete_resource(Req, #state{name=Name, type=props}=State) ->
    lmq:update_props(Name),
    {true, Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, #state{type=undefined}=State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}
     ], Req, State};
content_types_accepted(Req, #state{type=props}=State) ->
    {[{{<<"application">>, <<"json">>, '*'}, update_props}
     ], Req, State}.

to_json(Req, #state{method=Method}=State) ->
    to_json(Method, Req, State).

to_json(<<"GET">>, Req, #state{name=Name, type=undefined}=State) ->
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
    end;
to_json(<<"GET">>, Req, #state{name=Name, type=props}=State) ->
    {jsonx:encode(lmq_api:export_props(lmq:get_props(Name))), Req, State}.

process_post(Req, #state{name=Name}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    Packing = case lmq:push(Name, Content) of
        ok -> no;
        packing_started  -> created;
        packed -> appended
    end,
    Resp = jsonx:encode({[{packing, Packing}]}),
    {true, cowboy_req:set_resp_body(Resp, Req2), State}.

update_props(Req, #state{name=Name}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    case lmq_api:normalize_props(jsonx:decode(Content)) of
        {ok, Props} ->
            lmq:update_props(Name, Props),
            {true, Req2, State};
        {error, _} ->
            {false, Req2, State}
    end.
