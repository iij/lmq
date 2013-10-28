-module(lmq_cow_prop).

-export([init/3, rest_init/2, allowed_methods/2, delete_resource/2,
    content_types_provided/2, content_types_accepted/2]).
-export([to_json/2, update_props/2]).

-record(state, {method, name}).

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, []) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    {Method, Req3} = cowboy_req:method(Req2),
    {ok, Req3, #state{method=Method, name=Name}}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"PUT">>, <<"DELETE">>], Req, State}.

delete_resource(Req, #state{name=undefined}=State) ->
    lmq:set_default_props([]),
    {true, Req, State};
delete_resource(Req, #state{name=Name}=State) ->
    lmq:update_props(Name),
    {true, Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, update_props}
     ], Req, State}.

to_json(Req, #state{name=undefined}=State) ->
    {jsonx:encode(lmq_api:export_default_props(lmq:get_default_props())), Req, State};
to_json(Req, #state{name=Name}=State) ->
    {jsonx:encode(lmq_api:export_props(lmq:get_props(Name))), Req, State}.

update_props(Req, State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    update_props(jsonx:decode(Content), Req2, State).

update_props(Body, Req, #state{name=undefined}=State) ->
    case lmq_api:normalize_default_props(Body) of
        {ok, Props} ->
            lmq:set_default_props(Props),
            {true, Req, State};
        {error, _} ->
            {false, Req, State}
    end;
update_props(Body, Req, #state{name=Name}=State) ->
    case lmq_api:normalize_props(Body) of
        {ok, Props} ->
            lmq:update_props(Name, Props),
            {true, Req, State};
        {error, _} ->
            {false, Req, State}
    end.
