-module(lmq_queue).
-include("lmq.hrl").
-include_lib("stdlib/include/qlc.hrl").
-compile(export_all).

create_table() ->
    mnesia:create_schema([node()|nodes()]),
    mnesia:start(),
    mnesia:create_table(message, [
        {type, ordered_set},
        {attributes, record_info(fields, message)}
    ]),
    mnesia:stop().

drop_table() ->
    mnesia:start(),
    mnesia:delete_table(message),
    mnesia:stop(),
    mnesia:delete_schema([node()|nodes()]).

start() ->
    mnesia:start().

enqueue(Data) ->
    Message = new_message(Data),
    F = fun() -> mnesia:write(message, Message, write) end,
    transaction(F).

dequeue() ->
    F = fun() ->
        case mnesia:first(message) of
            '$end_of_table' ->
                empty;
            Key ->
                [M] = mnesia:read(message, Key, read),
                {TS, _} = M#message.id,
                Now = lmq_misc:unixtime(),
                case TS >= Now of
                    true ->
                        empty;
                    false ->
                        TS1 = Now + ?DEFAULT_TIMEOUT,
                        UUID1 = case M#message.processing of
                            true -> lmq_misc:uuid();
                            false -> M#message.uuid
                        end,
                        M1 = M#message{id={TS1, UUID1}, uuid=UUID1, processing=true},
                        mnesia:write(message, M1, write),
                        mnesia:delete(message, Key, write),
                        M1
                end
        end
    end,
    transaction(F).

complete(UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        [M] = qlc:e(qlc:q([X || X <- mnesia:table(message),
                           X#message.uuid =:= UUID,
                           element(1, X#message.id) >= Now])),
        mnesia:delete(message, M#message.id, write)
    end,
    case mnesia:transaction(F) of
        {atomic, _} -> ok;
        _ -> not_found
    end.

waittime() ->
    case first() of
        empty -> infinity;
        Message ->
            {TS, _} = Message#message.id,
            Timeout = round(TS - lmq_misc:unixtime()),
            lists:max([Timeout, 0])
    end.

new_message(Data) ->
    UUID = lmq_misc:uuid(),
    #message{id={lmq_misc:unixtime(), UUID}, uuid=UUID, processing=false, data=Data}.

first() ->
    F = fun() ->
        case mnesia:first(message) of
            '$end_of_table' -> empty;
            Key ->
                [Item] = mnesia:read(message, Key, read),
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
