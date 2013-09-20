-module(lmq_event).

-export([start_link/0, start_link/1, add_handler/1, notify/1, notify_remote/2,
    new_message/1]).

%% ==================================================================
%% Public API
%% ==================================================================

start_link() ->
    start_link(mnesia:system_info(extra_db_nodes)).

start_link(Nodes) ->
    {ok, Pid} = gen_event:start_link({local, ?MODULE}),
    gen_event:add_handler(?MODULE, lmq_handler_dist, [Nodes]),
    add_handler(lmq_handler),
    {ok, Pid}.

add_handler(Module) ->
    gen_event:add_handler(?MODULE, Module, []).

notify(Event) ->
    gen_event:notify(?MODULE, {local, Event}).

notify_remote(Node, Event) ->
    gen_event:notify({?MODULE, Node}, {remote, Event}).

new_message(QName) ->
    notify({new_message, QName}).
