-module(lmq_lib).

-include("lmq.hrl").
-include_lib("stdlib/include/qlc.hrl").
-export([create_admin_table/0, queue_info/1, all_queue_names/0, create/1,
    create/2, delete/1, enqueue/2, enqueue/3, dequeue/2, done/2, retain/3,
    release/2, first/1, waittime/1, export_message/1]).

create_admin_table() ->
    case mnesia:create_table(?QUEUE_INFO_TABLE, ?QUEUE_INFO_TABLE_DEFS) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, ?QUEUE_INFO_TABLE}} -> ok;
        Other ->
            lager:error("Failed to create admin table: ~p", [Other])
    end.

queue_info(Name) when is_atom(Name) ->
    F = fun() ->
        case qlc:e(qlc:q([P || #queue_info{name=N, props=P}
                               <- mnesia:table(?QUEUE_INFO_TABLE),
                               N =:= Name])) of
            [P] -> P;
            [] -> not_found
        end
    end,
    transaction(F).

all_queue_names() ->
    transaction(fun() ->
        qlc:e(qlc:q([N || #queue_info{name=N}
                          <- mnesia:table(?QUEUE_INFO_TABLE)]))
    end).

create(Name) when is_atom(Name) ->
    create(Name, []).

create(Name, Props) when is_atom(Name) ->
    Props1 = lmq_misc:extend(Props, ?DEFAULT_QUEUE_PROPS),
    Def = [
        {type, ordered_set},
        {attributes, record_info(fields, message)},
        {record_name, message}
    ],
    Info = #queue_info{name=Name, props=Props1},
    F = fun() -> mnesia:write(?QUEUE_INFO_TABLE, Info, write) end,

    case mnesia:create_table(Name, Def) of
        {atomic, ok} ->
            ok = transaction(F);
        {aborted, {already_exists, Name}} ->
            ok = transaction(F);
        Other ->
            lager:error("Failed to create table '~p': ~p", [Name, Other])
    end.

delete(Name) when is_atom(Name) ->
    F = fun() -> mnesia:delete(?QUEUE_INFO_TABLE, Name, write) end,
    transaction(F),
    case mnesia:delete_table(Name) of
        {atomic, ok} -> ok;
        {aborted, {no_exists, Name}} -> ok;
        Other ->
            lager:error("Failed to delete table '~p': ~p", [Name, Other])
    end.

enqueue(Name, Data) ->
    enqueue(Name, Data, []).

enqueue(Name, Data, Opts) ->
    Retry = proplists:get_value(retry, Opts, infinity),
    M = #message{data=Data, retry=Retry},
    F = fun() -> mnesia:write(Name, M, write) end,
    transaction(F).

dequeue(Name, Timeout) ->
    transaction(fun() -> get_first_message(Name, Timeout) end).

get_first_message(Name, Timeout) ->
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
                    mnesia:delete(Name, Key, write),
                    NewId = {Now + Timeout, uuid:get_v4()},
                    case M#message.retry of
                        infinity ->
                            NewMsg = M#message{id=NewId, state=processing},
                            mnesia:write(Name, NewMsg, write),
                            NewMsg;
                        N when N < 0 ->
                            get_first_message(Name, Timeout);
                        N ->
                            NewMsg = M#message{id=NewId, state=processing, retry=N-1},
                            mnesia:write(Name, NewMsg, write),
                            NewMsg
                    end
            end
    end.

done(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case qlc:e(qlc:q([X || X=#message{id={TS, ID}, state=processing} <- mnesia:table(Name),
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
        case qlc:e(qlc:q([X || X=#message{id={_, ID}, state=processing} <- mnesia:table(Name),
                               ID =:= UUID])) of
            [M] ->
                NewMsg = M#message{id={Now, UUID}, state=available},
                mnesia:write(Name, NewMsg, write),
                mnesia:delete(Name, M#message.id, write);
            [] ->
                not_found
        end
    end,
    transaction(F).

retain(Name, UUID, Timeout) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case qlc:e(qlc:q([X || X <- mnesia:table(Name),
                               element(2, X#message.id) =:= UUID,
                               element(1, X#message.id) >= Now])) of
            [M] ->
                M1 = M#message{id={Now + Timeout, UUID}},
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
