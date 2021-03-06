-module(lmq_console).

-export([join/1, leave/1, add_new_node/1, status/1, stats/1]).

join([NodeStr]) when is_list(NodeStr) ->
    Node = list_to_atom(NodeStr),
    join(Node);

join(Node) when is_atom(Node) ->
    case {net_kernel:connect_node(Node), net_adm:ping(Node)} of
        {true, pong} ->
            ok = application:stop(lmq),
            delete_local_schema(),
            R = rpc:call(Node, lmq_console, add_new_node, [node()]),
            ok = application:start(lmq),
            R;
        {_, pang} ->
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

status([]) ->
    Status = lmq:status(),
    io:format("   All nodes: ~s~n", [string:join(
        [atom_to_list(N) || N <- proplists:get_value(all_nodes, Status)],
        ", ")]),
    io:format("Active nodes: ~s~n", [string:join(
        [atom_to_list(N) || N <- proplists:get_value(active_nodes, Status)],
        ", ")]),
    io:format("~n"),
    lists:foreach(fun({Name, QStatus}) ->
        io:format("~s ~7.B messages ~15.B bytes~n", [
            string:left(atom_to_list(Name), 40),
            proplists:get_value(size, QStatus),
            proplists:get_value(memory, QStatus)
        ]),
        Props = proplists:get_value(props, QStatus),
        io:format("  accum: ~p, retry: ~B, timeout: ~p~n", [
            proplists:get_value(accum, Props) / 1000,
            proplists:get_value(retry, Props),
            proplists:get_value(timeout, Props) / 1
        ])
    end, proplists:get_value(queues, Status)),
    ok.

stats([]) ->
    lists:foreach(fun({Name, Info}) ->
        Push = proplists:get_value(push, Info),
        Pull = proplists:get_value(pull, Info),
        Retention = proplists:get_value(retention, Info),
        io:format("~s~n", [Name]),
        io:format("  push rate: 1min ~.2f, 5min ~.2f, 15min ~.2f, 1day ~.2f~n", [
            proplists:get_value(K, Push) || K <- [one, five, fifteen, day]]),
        io:format("  pull rate: 1min ~.2f, 5min ~.2f, 15min ~.2f, 1day ~.2f~n", [
            proplists:get_value(K, Pull) || K <- [one, five, fifteen, day]]),
        io:format("  retention time: min ~.3f, max ~.3f, mean ~.3f, median ~.3f~n", [
            proplists:get_value(K, Retention) || K <- [min, max, arithmetic_mean, median]])
    end, lmq:stats()).

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
