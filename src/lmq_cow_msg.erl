-module(lmq_cow_msg).

-export([init/3, rest_init/2, allowed_methods/2,
    content_types_provided/2, content_types_accepted/2]).
-export([to_json/2, process_post/2, export_push_resp/1]).

-record(state, {method, name}).

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, []) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    {ok, Req2, #state{name=binary_to_atom(Name, latin1)}}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, process_post}], Req, State}.

%% ==================================================================
%% Public functions
%% ==================================================================

to_json(Req, #state{name=Name}=State) ->
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
    Res = export_push_resp(lmq:push(Name, Content)),
    Res2 = jsonx:encode(Res),
    {true, cowboy_req:set_resp_body(Res2, Req2), State}.

export_push_resp(ok) ->
    {[{packing, no}]};
export_push_resp(packing_started) ->
    {[{packing, created}]};
export_push_resp(packed) ->
    {[{packing, appended}]}.
