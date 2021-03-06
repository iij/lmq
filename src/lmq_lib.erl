-module(lmq_lib).

-include("lmq.hrl").
-include_lib("stdlib/include/qlc.hrl").
-export([init_mnesia/0, create_admin_table/0,
    get_lmq_info/1, get_lmq_info/2, set_lmq_info/2,
    queue_info/1, update_queue_props/2, all_queue_names/0, create/1,
    create/2, delete/1, enqueue/2, enqueue/3, dequeue/2, done/2, retain/3,
    release/2, put_back/2, first/1, rfind/2, waittime/1, export_message/1,
    get_properties/1, get_properties/2]).

init_mnesia() ->
    case mnesia:system_info(db_nodes) =:= [node()] of
        true -> create_admin_table();
        false -> ok
    end.

create_admin_table() ->
    case mnesia:create_table(?LMQ_INFO_TABLE, ?LMQ_INFO_TABLE_DEFS) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, ?LMQ_INFO_TABLE}} -> ok;
        Other1 ->
            lager:error("Failed to create admin table: ~p", [Other1])
    end,
    case mnesia:create_table(?QUEUE_INFO_TABLE, ?QUEUE_INFO_TABLE_DEFS) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, ?QUEUE_INFO_TABLE}} -> ok;
        Other2 ->
            lager:error("Failed to create admin table: ~p", [Other2])
    end.

get_lmq_info(Key) ->
    transaction(fun() ->
        case mnesia:read(?LMQ_INFO_TABLE, Key) of
            [Info] -> {ok, Info#lmq_info.value};
            _ -> {error, not_found}
        end
    end).

get_lmq_info(Key, Default) ->
    case get_lmq_info(Key) of
        {ok, _}=R -> R;
        {error, _} -> {ok, Default}
    end.

set_lmq_info(Key, Value) ->
    Info = #lmq_info{key=Key, value=Value},
    transaction(fun() ->
        ok = mnesia:write(?LMQ_INFO_TABLE, Info, write)
    end).

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

update_queue_props(Name, Props) when is_atom(Name) ->
    Info = #queue_info{name=Name, props=Props},
    transaction(fun() ->
        mnesia:write(?QUEUE_INFO_TABLE, Info, write)
    end).

all_queue_names() ->
    transaction(fun() ->
        qlc:e(qlc:q([N || #queue_info{name=N}
                          <- mnesia:table(?QUEUE_INFO_TABLE)]))
    end).

create(Name) when is_atom(Name) ->
    create(Name, []).

create(Name, Props) when is_atom(Name) ->
    Def = [
        {type, ordered_set},
        {attributes, record_info(fields, message)},
        {record_name, message},
        {ram_copies, mnesia:system_info(db_nodes)}
    ],
    Info = #queue_info{name=Name, props=Props},
    F = fun() -> mnesia:write(?QUEUE_INFO_TABLE, Info, write) end,

    case mnesia:create_table(Name, Def) of
        {atomic, ok} ->
            ok = transaction(F),
            lmq_event:queue_created(Name);
        {aborted, {already_exists, Name}} ->
            case queue_info(Name) of
                Props ->
                    ok;
                _ ->
                    ok = transaction(F),
                    lmq_event:queue_created(Name)
            end;
        Other ->
            lager:error("Failed to create table '~p': ~p", [Name, Other])
    end.

delete(Name) when is_atom(Name) ->
    F = fun() -> mnesia:delete(?QUEUE_INFO_TABLE, Name, write) end,
    transaction(F),
    case mnesia:delete_table(Name) of
        {atomic, ok} ->
            lmq_event:queue_deleted(Name),
            ok;
        {aborted, {no_exists, Name}} ->
            ok;
        Other ->
            lager:error("Failed to delete table '~p': ~p", [Name, Other])
    end.

enqueue(Name, Content) ->
    enqueue(Name, Content, []).

enqueue(Name, Content, Opts) ->
    case proplists:get_value(accum, Opts, 0) == 0 of
        true ->
            Retry = increment(proplists:get_value(retry, Opts, infinity)),
            Msg = #message{content=Content, retry=Retry},
            transaction(fun() -> mnesia:write(Name, Msg, write) end);
        false -> %% accumulate duration in milliseconds
            accumulate_message(Name, Content, Opts)
    end.

accumulate_message(Name, Content, Opts) ->
    transaction(fun() ->
        QC = qlc:cursor(qlc:q([M || M=#message{id={TS, _}, state=accum}
                                    <- mnesia:table(Name),
                                    TS >= lmq_misc:unixtime()])),
        {Ret, Msg} = case qlc:next_answers(QC, 1) of
            [M] -> %% accumulating process already started
                Content1 = M#message.content ++ [Content],
                {{accum, yes}, M#message{content=Content1}};
            [] -> %% add new message for accumulating
                Retry = increment(proplists:get_value(retry, Opts, infinity)),
                Duration = proplists:get_value(accum, Opts),
                Id={lmq_misc:unixtime() + Duration / 1000, uuid:get_v4()},
                {{accum, new}, #message{id=Id, state=accum, type=compound,
                                        retry=Retry, content=[Content]}}
        end,
        mnesia:write(Name, Msg, write),
        ok = qlc:delete_cursor(QC),
        Ret
    end).

dequeue(Name, Timeout) ->
    case transaction(fun() -> get_first_message(Name, Timeout) end) of
        {ok, Msg, Retention} ->
            lmq_metrics:update_metric(Name, retention, Retention),
            Msg;
        continue ->
            dequeue(Name, Timeout);
        Other ->
            Other
    end.

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
                            {ok, NewMsg, Now - TS};
                        N when N > 0 ->
                            NewMsg = M#message{id=NewId, state=processing, retry=N-1},
                            mnesia:write(Name, NewMsg, write),
                            {ok, NewMsg, Now - TS};
                        _ ->
                            %% quit transaction to avoid infinite loop caused by
                            %% large amount of waste messages
                            continue
                    end
            end
    end.

increment(infinity) ->
    infinity;

increment(Number) when is_integer(Number) ->
    Number + 1.

done(Name, UUID) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case rfind(Name, UUID) of
            '$end_of_table' ->
                not_found;
            #message{id={TS, UUID}} when TS < Now ->
                not_found;
            #message{id=Key, state=processing} ->
                mnesia:delete(Name, Key, write);
            _ ->
                not_found
        end
    end,
    transaction(F).

release(Name, UUID) ->
    put_back(Name, UUID, consume).

put_back(Name, UUID) ->
    put_back(Name, UUID, keep).

put_back(Name, UUID, Retry) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case rfind(Name, UUID) of
            '$end_of_table' ->
                not_found;
            #message{id={TS, UUID}} when TS < Now ->
                not_found;
            #message{state=processing, retry=R}=M ->
                M1 = if Retry =:= consume ->
                    M#message{id={Now, UUID}, state=available, retry=R};
                true ->
                    M#message{id={Now, UUID}, state=available, retry=increment(R)}
                end,
                mnesia:write(Name, M1, write),
                mnesia:delete(Name, M#message.id, write);
            _ ->
                not_found
        end
    end,
    transaction(F).

retain(Name, UUID, Timeout) ->
    Now = lmq_misc:unixtime(),
    F = fun() ->
        case rfind(Name, UUID) of
            '$end_of_table' ->
                not_found;
            #message{id={TS, UUID}} when TS < Now ->
                not_found;
            #message{state=processing}=M ->
                M1 = M#message{id={Now + Timeout, UUID}},
                mnesia:write(Name, M1, write),
                mnesia:delete(Name, M#message.id, write);
            _ ->
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
            Timeout = round((TS - lmq_misc:unixtime()) * 1000),
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

rfind(Tab, Id) ->
    F = fun(M, _Acc) when element(2, M#message.id) =:= Id ->
            %% break loop, throw will be handled by foldr
            throw(M);
        (_, Acc) -> Acc
    end,
    mnesia:foldr(F, '$end_of_table', Tab).

transaction(F) ->
    case mnesia:transaction(F) of
        {atomic, Val} -> Val;
        {aborted, {no_exists, _}} -> {error, no_queue_exists};
        {aborted, Reason} -> {error, Reason}
    end.

get_properties(Name) ->
    Base = get_props(Name),
    case lmq_lib:queue_info(Name) of
        not_found -> Base;
        Props -> lmq_misc:extend(Props, Base)
    end.

get_properties(Name, Override) ->
    Props = get_properties(Name),
    lmq_misc:extend(Override, Props).

get_props(Name) ->
    {ok, DefaultProps} = get_lmq_info(default_props, []),
    get_props(Name, DefaultProps).

get_props(_Name, []) ->
    ?DEFAULT_QUEUE_PROPS;

get_props(Name, PropsList) when is_atom(Name) ->
    get_props(atom_to_list(Name), PropsList);

get_props(Name, [{Regexp, Props} | T]) when is_list(Name) ->
    {ok, MP} = re:compile(Regexp),
    case re:run(Name, MP) of
        {match, _} -> lmq_misc:extend(Props, ?DEFAULT_QUEUE_PROPS);
        _ -> get_props(Name, T)
    end.

export_message(M=#message{}) ->
    UUID = list_to_binary(uuid:uuid_to_string(element(2, M#message.id))),
    [{id, UUID}, {type, M#message.type}, {retry, M#message.retry}, {content, M#message.content}].

%% ==================================================================
%% EUnit tests
%% ==================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

get_props_test() ->
    DefaultProps = [{"lmq", [{retry, 0}]}],
    Props = lmq_misc:extend([{retry, 0}], ?DEFAULT_QUEUE_PROPS),
    ?assertEqual(Props, get_props(lmq, DefaultProps)),
    ?assertEqual(Props, get_props("lmq", DefaultProps)),
    ?assertEqual(?DEFAULT_QUEUE_PROPS, get_props("foo", DefaultProps)),
    ?assertEqual(?DEFAULT_QUEUE_PROPS, get_props("lmq", [])).

export_message_test() ->
    Ref = make_ref(),
    M = #message{content=Ref},
    UUID = list_to_binary(uuid:uuid_to_string(element(2, M#message.id))),
    ?assertEqual([{id, UUID}, {type, normal}, {retry, 0}, {content, Ref}],
                 export_message(M)),

    M2 = M#message{type=compound, retry=1},
    ?assertEqual([{id, UUID}, {type, compound}, {retry, 1}, {content, Ref}],
                 export_message(M2)).

-endif.
