-module(lmq_cow_queue).

-export([init/3, rest_init/2, allowed_methods/2, resource_exists/2, delete_resource/2]).

-record(state, {name}).

init(_Transport, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, []) ->
    {Name, Req2} = cowboy_req:binding(name, Req),
    {ok, Req2, #state{name=binary_to_atom(Name, latin1)}}.

allowed_methods(Req, State) ->
    {[<<"DELETE">>], Req, State}.

resource_exists(Req, #state{name=Name}=State) ->
    {lmq_queue_mgr:get(Name) =/= not_found, Req, State}.

delete_resource(Req, #state{name=Name}=State) ->
    ok = lmq:delete(Name),
    {true, Req, State}.
