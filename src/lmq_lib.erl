-module(lmq_lib).

-include("lmq.hrl").
-include_lib("stdlib/include/qlc.hrl").
-compile(export_all).

create(Name) when is_atom(Name) ->
    Def = [
        {type, ordered_set},
        {attributes, record_info(fields, message)},
        {record_name, message}
    ],
    case mnesia:create_table(Name, Def) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} -> ok;
        Other -> Other
    end.

enqueue(Name, Data) ->
    M = #message{data=Data},
    F = fun() -> mnesia:write(Name, M, write) end,
    transaction(F).

dequeue(Name) ->
    F = fun() ->
        case mnesia:first(Name) of
            '$end_of_table' ->
                empty;
            Key ->
                [M] = mnesia:read(Name, Key, read),
                {TS, _} = M#message.id,
                Now = lmq_misc:unixtime(),
                case TS > Now of
                    true ->
                        empty;
                    false ->
                        NewId = {Now + ?DEFAULT_TIMEOUT, lmq_misc:uuid()},
                        NewMsg = M#message{id=NewId, active=true},
                        mnesia:write(Name, NewMsg, write),
                        mnesia:delete(Name, Key, write),
                        NewMsg
                end
        end
    end,
    transaction(F).

complete(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        [M] = qlc:e(qlc:q([X || X=#message{id={TS, ID}, active=true} <- mnesia:table(Name),
                                ID =:= UUID, TS >= Now])),
        mnesia:delete(Name, M#message.id, write)
    end,
    case mnesia:transaction(F) of
        {atomic, _} -> ok;
        _ -> not_found
    end.

return(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        [M] = qlc:e(qlc:q([X || X=#message{id={_, ID}, active=true} <- mnesia:table(Name),
                                ID =:= UUID])),
        NewMsg = M#message{id={Now, UUID}, active=false},
        mnesia:write(Name, NewMsg, write),
        mnesia:delete(Name, M#message.id, write)
    end,
    case mnesia:transaction(F) of
        {atomic, _} -> ok;
        _ -> not_found
    end.

reset_timeout(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        [M] = qlc:e(qlc:q([X || X <- mnesia:table(Name),
                           element(2, X#message.id) =:= UUID,
                           element(1, X#message.id) >= Now])),
        M1 = M#message{id={Now + ?DEFAULT_TIMEOUT, UUID}},
        mnesia:write(Name, M1, write),
        mnesia:delete(Name, M#message.id, write)
    end,
    case mnesia:transaction(F) of
        {atomic, _} -> ok;
        _ -> not_found
    end.

waittime(Name) ->
    case first(Name) of
        empty -> infinity;
        Message ->
            {TS, _} = Message#message.id,
            Timeout = round(TS - lmq_misc:unixtime()),
            lists:max([Timeout, 0])
    end.

first(Name) ->
    F = fun() ->
        case mnesia:first(Name) of
            '$end_of_table' -> empty;
            Key ->
                [Item] = mnesia:read(Name, Key, read),
                Item
        end
    end,
    transaction(F).

get_all() ->
    select(qlc:q([X || X <- mnesia:table(message)])).

select(Q) ->
    F = fun() -> qlc:e(Q) end,
    {atomic, Val} = mnesia:transaction(F),
    Val.

transaction(F) ->
    {atomic, Val} = mnesia:transaction(F),
    Val.
