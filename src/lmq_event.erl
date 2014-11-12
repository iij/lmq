-module(lmq_event).

-export([start_link/0, start_link/1, add_handler/1, add_handler/2,
    notify/1, notify_remote/2]).
-export([queue_created/1, queue_deleted/1, new_message/1]).

%% ==================================================================
%% Public API
%% ==================================================================

start_link() ->
    Nodes = [N || N <- mnesia:system_info(running_db_nodes),
                  N =/= node()],
    start_link(Nodes).

start_link(Nodes) ->
    {ok, Pid} = gen_event:start_link({local, ?MODULE}),
    add_handler(lmq_handler_dist, [Nodes]),
    add_handler(lmq_handler),
    {ok, Pid}.

add_handler(Module) ->
    add_handler(Module, []).

add_handler(Module, Args) ->
    gen_event:add_handler(?MODULE, Module, Args).

notify(Event) ->
    gen_event:notify(?MODULE, {local, Event}).

notify_remote(Node, Event) ->
    gen_event:notify({?MODULE, Node}, {remote, Event}).

queue_created(Name) ->
    notify({queue_created, Name}).

queue_deleted(Name) ->
    notify({queue_deleted, Name}).

new_message(QName) ->
    notify({new_message, QName}).
