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
    {ok, Req3, #state{method=Method,
                      name=binary_to_atom(Name, latin1)}}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"PUT">>, <<"DELETE">>], Req, State}.

delete_resource(Req, #state{name=Name}=State) ->
    lmq:update_props(Name),
    {true, Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, to_json}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {[{{<<"application">>, <<"json">>, '*'}, update_props}
     ], Req, State}.

to_json(Req, #state{name=Name}=State) ->
    {jsonx:encode(lmq_api:export_props(lmq:get_props(Name))), Req, State}.

update_props(Req, #state{name=Name}=State) ->
    {ok, Content, Req2} = cowboy_req:body(Req),
    case lmq_api:normalize_props(jsonx:decode(Content)) of
        {ok, Props} ->
            lmq:update_props(Name, Props),
            {true, Req2, State};
        {error, _} ->
            {false, Req2, State}
    end.
