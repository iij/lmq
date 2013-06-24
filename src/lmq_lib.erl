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
                        NewId = {Now + ?DEFAULT_TIMEOUT, uuid:get_v4()},
                        NewMsg = M#message{id=NewId, active=true},
                        mnesia:write(Name, NewMsg, write),
                        mnesia:delete(Name, Key, write),
                        NewMsg
                end
        end
    end,
    transaction(F).

done(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case qlc:e(qlc:q([X || X=#message{id={TS, ID}, active=true} <- mnesia:table(Name),
                               ID =:= UUID, TS >= Now])) of
            [M] ->
                mnesia:delete(Name, M#message.id, write);
            [] ->
                not_found
        end
    end,
    transaction(F).

release(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case qlc:e(qlc:q([X || X=#message{id={_, ID}, active=true} <- mnesia:table(Name),
                               ID =:= UUID])) of
            [M] ->
                NewMsg = M#message{id={Now, UUID}, active=false},
                mnesia:write(Name, NewMsg, write),
                mnesia:delete(Name, M#message.id, write);
            [] ->
                not_found
        end
    end,
    transaction(F).

retain(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case qlc:e(qlc:q([X || X <- mnesia:table(Name),
                               element(2, X#message.id) =:= UUID,
                               element(1, X#message.id) >= Now])) of
            [M] ->
                M1 = M#message{id={Now + ?DEFAULT_TIMEOUT, UUID}},
                mnesia:write(Name, M1, write),
                mnesia:delete(Name, M#message.id, write);
            [] ->
                not_found
        end
    end,
    transaction(F).

waittime(Name) ->
    case first(Name) of
        {error, _}=E -> E;
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
    case mnesia:transaction(F) of
        {atomic, Val} -> Val;
        {aborted, {no_exists, _}} -> {error, no_queue_exists};
        {aborted, Reason} -> {error, Reason}
    end.

export_message(M=#message{}) ->
    {_, UUID} = M#message.id,
    UUID1 = list_to_binary(uuid:uuid_to_string(UUID)),
    {[{<<"id">>, UUID1}, {<<"content">>, M#message.data}]}.


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

export_message_test() ->
    Ref = make_ref(),
    M = #message{data=Ref},
    {_, UUID} = M#message.id,
    UUID1 = list_to_binary(uuid:uuid_to_string(UUID)),
    ?assertEqual({[{<<"id">>, UUID1}, {<<"content">>, Ref}]}, export_message(M)).

-endif.
