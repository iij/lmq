-module(lmq_console).

-export([join/1, add_new_node/1]).

join([NodeStr]) when is_list(NodeStr) ->
    Node = list_to_atom(NodeStr),
    join(Node);

join(Node) when is_atom(Node) ->
    case net_adm:ping(Node) of
        pong ->
            delete_local_schema(),
            rpc:call(Node, lmq_console, add_new_node, [node()]);
        pang ->
            {error, not_reachable}
    end.

delete_local_schema() ->
    ok = application:stop(mnesia),
    ok = mnesia:delete_schema([node()]),
    ok = application:start(mnesia).

add_new_node(Node) ->
    case mnesia:change_config(extra_db_nodes, [Node]) of
        {ok, _} -> copy_all_tables(Node);
        {error, _}=E -> E
    end.

copy_all_tables(Node) ->
    Tables = mnesia:system_info(tables),
    Errors = lists:foldl(fun(Tab, Failed) ->
        case mnesia:add_table_copy(Tab, Node, ram_copies) of
            {atomic, ok} -> Failed;
            {aborted, {already_exists, _, _}} -> Failed;
            {aborted, Reason} -> [{Tab, Reason} | Failed]
        end
    end, [], Tables),
    case Errors of
        [] -> ok;
        Other -> {error, {copy_failed, Other}}
    end.
