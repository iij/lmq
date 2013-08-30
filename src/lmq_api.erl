-module(lmq_api).

-export([delete/1, push/2, pull/1, pull/2, push_all/2,
    pull_any/1, pull_any/2, done/2, retain/2, release/2,
    update_props/1, update_props/2]).
-include("lmq.hrl").

delete(Name) when is_binary(Name) ->
    lager:info("lmq_api:delete(~s)", [Name]),
    Name1 = binary_to_atom(Name, latin1),
    ok = lmq_queue_mgr:delete(Name1),
    <<"ok">>.

push(Name, Content) when is_binary(Name) ->
    lager:info("lmq_api:push(~s, ...)", [Name]),
    lmq:push(binary_to_atom(Name, latin1), Content),
    <<"ok">>.

pull(Name) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s)", [Name]),
    lmq:pull(binary_to_atom(Name, latin1)).

pull(Name, Timeout) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s, ~p)", [Name, Timeout]),
    lmq:pull(binary_to_atom(Name, latin1), Timeout).

push_all(Regexp, Content) when is_binary(Regexp) ->
    lager:info("lmq_api:push_all(~s, ...)", [Regexp]),
    Queues = case lmq_queue_mgr:match(Regexp) of
        {error, Reason} -> throw(Reason);
        Other -> Other
    end,
    [lmq_queue:push(Q, Content) || Q <- Queues],
    <<"ok">>.

pull_any(Regexp) ->
    pull_any(Regexp, inifinity).

pull_any(Regexp, Timeout) when is_binary(Regexp) ->
    lager:info("lmq_api:pull_any(~s, ~p)", [Regexp, Timeout]),
    Timeout1 = case Timeout of
        inifinity -> infinity;
        0 -> infinity;
        Float -> round(Float * 1000)
    end,
    Queues = case lmq_queue_mgr:match(Regexp) of
        {error, Reason} -> throw(Reason);
        Other -> Other
    end,
    Mapping = lists:foldl(fun(Q, Acc) ->
        Id = lmq_queue:pull_async(Q, Timeout),
        dict:store(Id, Q, Acc)
    end, dict:new(), Queues),
    %% waiting for asynchronous response
    receive
        {Id, M=#message{}} ->
            cancel_pull(dict:erase(Id, Mapping)),
            lmq_lib:export_message(M);
        {Id, {error, _Reason}} ->
            cancel_pull(dict:erase(Id, Mapping)),
            <<"empty">>
    after Timeout1 ->
        cancel_pull(Mapping),
        <<"empty">>
    end.

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

update_props(Name) when is_binary(Name) ->
    lager:info("lmq_api:update_props(~s)", [Name]),
    lmq:update_props(binary_to_atom(Name, latin1)),
    <<"ok">>.

update_props(Name, Props) when is_binary(Name) ->
    lager:info("lmq_api:update_props(~s, ~p)", [Name, Props]),
    lmq:update_props(binary_to_atom(Name, latin1), normalize_props(Props)),
    <<"ok">>.

find(Name) when is_binary(Name) ->
    Name1 = binary_to_atom(Name, latin1),
    case lmq_queue_mgr:get(Name1) of
        not_found -> throw(queue_not_found);
        Pid -> Pid
    end.

cancel_pull(Mapping) ->
    dict:map(fun(I, Q) -> lmq_queue:pull_cancel(Q, I) end, Mapping),
    release_messages(Mapping).

release_messages(Mapping) ->
    receive
        {Id, M=#message{}} ->
            Q = dict:fetch(Id, Mapping),
            {_, UUID} = M#message.id,
            lmq_queue:release(Q, UUID),
            release_messages(Mapping);
        {_Id, {error, _Reason}} ->
            ok
    after 0 ->
        ok
    end.

convert_uuid(UUID) when is_binary(UUID) ->
    uuid:string_to_uuid(binary_to_list(UUID)).

normalize_props({Props}) ->
    %% jiffy style to proplists
    normalize_props(Props, []).

normalize_props([{<<"pack">>, Duration} | T], Acc) ->
    normalize_props(T, [{pack, round(Duration * 1000)} | Acc]);
normalize_props([{K, V} | T], Acc) ->
    normalize_props(T, [{binary_to_atom(K, latin1), V} | Acc]);
normalize_props([], Acc) ->
    lists:reverse(Acc).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

normalize_props_test() ->
    ?assertEqual(normalize_props({[{<<"retry">>, 3}, {<<"timeout">>, 5.0},
                                  {<<"pack">>, 0.5}]}),
                 [{retry, 3}, {timeout, 5.0}, {pack, 500}]).

-endif.
