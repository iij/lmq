-module(lmq).

-include("lmq.hrl").
-export([start/0, stop/0]).
-export([push/2, pull/1, pull/2, pull/3, ack/2, abort/2, keep/2,
    push_all/2, pull_any/1, pull_any/2, pull_any/3, delete/1,
    get_props/1, update_props/1, update_props/2,
    set_default_props/1, get_default_props/0,
    status/0, queue_status/1, stats/0, stats/1]).

-define(DEPS, [lager, crypto, quickrand, uuid, msgpack, msgpack_rpc,
    mnesia, ranch, cowlib, cowboy, jsonx, folsom, lmq]).

%% ==================================================================
%% Public API
%% ==================================================================

start() ->
    [ensure_started(Dep) || Dep <- ?DEPS],
    lager:set_loglevel(lager_console_backend, debug).

stop() ->
    [application:stop(Dep) || Dep <- lists:reverse(?DEPS)],
    ok.

push(Name, Content) when is_binary(Name) ->
    push(binary_to_atom(Name, latin1), Content);
push(Name, Content) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    lmq_queue:push(Pid, Content).

pull(Name) when is_binary(Name) ->
    pull(binary_to_atom(Name, latin1));
pull(Name) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    Msg = lmq_queue:pull(Pid),
    [{queue, Name} | lmq_lib:export_message(Msg)].

pull(Name, Timeout) when is_binary(Name) ->
    pull(binary_to_atom(Name, latin1), Timeout);
pull(Name, Timeout) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    case lmq_queue:pull(Pid, Timeout) of
        empty -> empty;
        Msg -> [{queue, Name} | lmq_lib:export_message(Msg)]
    end.

pull(Name, Timeout, Monitor) when is_binary(Name) ->
    pull(binary_to_atom(Name, latin1), Timeout, Monitor);
pull(Name, Timeout, Monitor) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    Id = lmq_queue:pull_async(Pid, Timeout),
    Wait = case Timeout of
        infinity -> infinity;
        0 -> infinity;
        N -> round(N * 1000)
    end,
    MonitorRef = erlang:monitor(process, Monitor),
    R = receive
        {Id, {error, timeout}} -> empty;
        {Id, Msg} -> [{queue, Name} | lmq_lib:export_message(Msg)];
        {'DOWN', MonitorRef, process, Monitor, _} ->
            lmq_queue:pull_cancel(Pid, Id),
            receive
                {Id, #message{id={_, UUID}}} -> lmq_queue:release(Pid, UUID)
            after 0 -> ok
            end,
            {error, down}
    after Wait ->
        empty
    end,
    erlang:demonitor(MonitorRef, [flush]),
    R.

ack(Name, UUID) ->
    process_message(done, Name, UUID).

abort(Name, UUID) ->
    process_message(release, Name, UUID).

keep(Name, UUID) ->
    process_message(retain, Name, UUID).

push_all(Regexp, Content) when is_binary(Regexp) ->
    case lmq_queue_mgr:match(Regexp) of
        {error, _}=R ->
            R;
        Queues ->
            {ok, [{Name, lmq_queue:push(Pid, Content)} || {Name, Pid} <- Queues]}
    end.

pull_any(Regexp) ->
    pull_any(Regexp, inifinity).

pull_any(Regexp, Timeout) when is_binary(Regexp) ->
    {ok, Pid} = lmq_mpull:start(),
    lmq_mpull:pull(Pid, Regexp, Timeout).

pull_any(Regexp, Timeout, Monitor) when is_binary(Regexp) ->
    {ok, Pid} = lmq_mpull:start(),
    {ok, Ref} = lmq_mpull:pull_async(Pid, Regexp, Timeout),
    MonitorRef = erlang:monitor(process, Monitor),
    receive
        {Ref, Msg} ->
            erlang:demonitor(MonitorRef, [flush]),
            Msg;
        {'DOWN', MonitorRef, process, Monitor, _} ->
            lmq_mpull:pull_cancel(Pid),
            receive
                {Ref, [{queue, Name}, {id, UUID}, _, _]} ->
                    Q = lmq_queue_mgr:get(Name, [create]),
                    lmq_queue:release(Q, UUID)
            after 0 -> ok
            end,
            {error, down}
    end.

delete(Name) when is_binary(Name) ->
    delete(binary_to_atom(Name, latin1));
delete(Name) when is_atom(Name) ->
    lmq_queue_mgr:delete(Name).

get_props(Name) when is_binary(Name) ->
    get_props(binary_to_atom(Name, latin1));
get_props(Name) when is_atom(Name) ->
    lmq_lib:get_properties(Name).

update_props(Name) ->
    update_props(Name, []).

update_props(Name, Props) when is_binary(Name) ->
    update_props(binary_to_atom(Name, latin1), Props);
update_props(Name, Props) when is_atom(Name) ->
    lmq_queue_mgr:get(Name, [create, update, {props, Props}]).

set_default_props(Props) ->
    lmq_queue_mgr:set_default_props(Props).

get_default_props() ->
    lmq_queue_mgr:get_default_props().

status() ->
    [{active_nodes, lists:sort(mnesia:system_info(running_db_nodes))},
     {all_nodes, lists:sort(mnesia:system_info(db_nodes))},
     {queues, [{N, queue_status(N)} || N <- lists:sort(lmq_lib:all_queue_names())]}
    ].

queue_status(Name) ->
    [{size, mnesia:table_info(Name, size)},
     {memory, mnesia:table_info(Name, memory) * erlang:system_info(wordsize)},
     {nodes, mnesia:table_info(Name, where_to_write)},
     {props, lmq_lib:get_properties(Name)}
    ].

stats() ->
    [stats(N) || N <- lists:sort(lmq_lib:all_queue_names())].

stats(Name) when is_atom(Name) ->
    {Name, [{push, lmq_metrics:get_metric(Name, push)},
            {pull, lmq_metrics:get_metric(Name, pull)},
            {retention, lmq_metrics:get_metric(Name, retention)}
    ]}.

%% ==================================================================
%% Private functions
%% ==================================================================

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.

process_message(Fun, Name, UUID) when is_atom(Fun), is_binary(Name) ->
    process_message(Fun, binary_to_atom(Name, latin1), UUID);
process_message(Fun, Name, UUID) when is_atom(Fun), is_atom(Name) ->
    case lmq_queue_mgr:get(Name) of
        not_found ->
            {error, queue_not_found};
        Pid ->
            try parse_uuid(UUID) of
                MsgId ->
                    case lmq_queue:Fun(Pid, MsgId) of
                        ok -> ok;
                        not_found -> {error, not_found}
                    end
            catch exit:badarg ->
                {error, not_found}
            end
    end.

parse_uuid(UUID) when is_binary(UUID) ->
    parse_uuid(binary_to_list(UUID));
parse_uuid(UUID) when is_list(UUID) ->
    uuid:string_to_uuid(UUID);
parse_uuid(UUID) ->
    UUID.
