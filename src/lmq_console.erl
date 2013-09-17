-module(lmq_console).

-export([join/1, leave/1, add_new_node/1]).

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

leave([]) ->
    RunningNodes = [Node || Node <- mnesia:system_info(running_db_nodes),
                             Node =/= node()],
    ok = application:stop(lmq),
    ok = application:stop(mnesia),
    R = case leave_cluster(RunningNodes) of
        ok -> ok = mnesia:delete_schema([node()]);
        Other -> Other
    end,
    ok = application:start(mnesia),
    ok = application:start(lmq),
    R.

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

leave_cluster([Node | Rest]) when is_atom(Node) ->
    case rpc:call(Node, mnesia, del_table_copy, [schema, node()]) of
        {atomic, ok} ->
            ok;
        {aborted, Reason} ->
            case Rest of
                [] -> {error, Reason};
                _ -> leave_cluster(Rest)
            end
    end.
