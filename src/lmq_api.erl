-module(lmq_api).

-export([create/1, push/2, pull/1, done/2, retain/2, release/2]).

create(Name) when is_binary(Name) ->
    lager:info("lmq_api:create(~s)", [Name]),
    Name1 = binary_to_atom(Name, latin1),
    ok = lmq_queue_mgr:create(Name1),
    <<"ok">>.

push(Name, Msg) when is_binary(Name) ->
    lager:info("lmq_api:push(~s, ~p)", [Name, Msg]),
    Pid = find(Name),
    lmq_queue:push(Pid, Msg),
    <<"ok">>.

pull(Name) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s)", [Name]),
    Pid = find(Name),
    M = lmq_queue:pull(Pid),
    lmq_lib:export_message(M).

done(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:done(~s, ~s)", [Name, UUID]),
    Pid = find(Name),
    UUID1 = convert_uuid(UUID),
    case lmq_queue:done(Pid, UUID1) of
        ok -> <<"ok">>;
        not_found -> throw(not_found)
    end.

retain(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:retain(~s, ~s)", [Name, UUID]),
    Pid = find(Name),
    UUID1 = convert_uuid(UUID),
    case lmq_queue:retain(Pid, UUID1) of
        ok -> <<"ok">>;
        not_found -> throw(not_found)
    end.

release(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:release(~s, ~s)", [Name, UUID]),
    Pid = find(Name),
    UUID1 = convert_uuid(UUID),
    case lmq_queue:release(Pid, UUID1) of
        ok -> <<"ok">>;
        not_found -> throw(not_found)
    end.

find(Name) when is_binary(Name) ->
    Name1 = binary_to_atom(Name, latin1),
    case lmq_queue_mgr:find(Name1) of
        not_found -> throw(queue_not_found);
        Pid -> Pid
    end.

convert_uuid(UUID) when is_binary(UUID) ->
    uuid:string_to_uuid(binary_to_list(UUID)).
