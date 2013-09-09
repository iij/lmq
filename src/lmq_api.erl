-module(lmq_api).

-export([delete/1, push/2, pull/1, pull/2, push_all/2,
    pull_any/1, pull_any/2, done/2, retain/2, release/2,
    update_props/1, update_props/2, set_default_props/1, get_default_props/0]).
-include("lmq.hrl").

delete(Name) when is_binary(Name) ->
    lager:info("lmq_api:delete(~s)", [Name]),
    Name1 = binary_to_atom(Name, latin1),
    ok = lmq_queue_mgr:delete(Name1),
    <<"ok">>.

push(Name, Content) when is_binary(Name) ->
    lager:info("lmq_api:push(~s, ...)", [Name]),
    case lmq:push(binary_to_atom(Name, latin1), Content) of
        packing_started -> <<"packing started">>;
        Other -> list_to_binary(atom_to_list(Other))
    end.

pull(Name) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s)", [Name]),
    {Response} = lmq:pull(binary_to_atom(Name, latin1)),
    {[{<<"queue">>, Name} | Response]}.

pull(Name, Timeout) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s, ~p)", [Name, Timeout]),
    case lmq:pull(binary_to_atom(Name, latin1), Timeout) of
        <<"empty">> -> <<"empty">>;
        {Response} -> {[{<<"queue">>, Name} | Response]}
    end.

push_all(Regexp, Content) when is_binary(Regexp) ->
    lager:info("lmq_api:push_all(~s, ...)", [Regexp]),
    Queues = case lmq_queue_mgr:match(Regexp) of
        {error, Reason} -> throw(Reason);
        Other -> Other
    end,
    [lmq_queue:push(Pid, Content) || {_, Pid} <- Queues],
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
    Mapping = lists:foldl(fun({_, Pid}=Q, Acc) ->
        Id = lmq_queue:pull_async(Pid, Timeout),
        dict:store(Id, Q, Acc)
    end, dict:new(), Queues),
    %% waiting for asynchronous response
    wait_pull_any_response(Mapping, Timeout1).

wait_pull_any_response(Mapping, Timeout) ->
    receive
        {Id, M=#message{}} ->
            {Name, _} = dict:fetch(Id, Mapping),
            cancel_pull(dict:erase(Id, Mapping)),
            {Response} = lmq_lib:export_message(M),
            {[{<<"queue">>, atom_to_binary(Name)} | Response]};
        {Id, {error, Reason}} ->
            Mapping1 = dict:erase(Id, Mapping),
            lager:debug("pull_any for ~p: ~p, rest ~p",
                [element(1, dict:fetch(Id, Mapping)), Reason, dict:size(Mapping1)]),
            case dict:size(Mapping1) of
                0 -> <<"empty">>;
                _ -> wait_pull_any_response(Mapping1, 10)
            end
    after Timeout ->
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

set_default_props(PropsList) ->
    lager:info("lmq_api:set_default_props(~p)", [PropsList]),
    case lmq:set_default_props(normalize_default_props(PropsList)) of
        ok -> <<"ok">>;
        Reason -> throw(Reason)
    end.

get_default_props() ->
    lager:info("lmq_api:get_default_props()"),
    export_default_props(lmq:get_default_props()).

find(Name) when is_binary(Name) ->
    Name1 = binary_to_atom(Name, latin1),
    case lmq_queue_mgr:get(Name1) of
        not_found -> throw(queue_not_found);
        Pid -> Pid
    end.

cancel_pull(Mapping) ->
    dict:map(fun(Id, {_, Pid}) -> lmq_queue:pull_cancel(Pid, Id) end, Mapping),
    release_messages(Mapping).

release_messages(Mapping) ->
    receive
        {Id, M=#message{}} ->
            {_, Pid} = dict:fetch(Id, Mapping),
            {_, UUID} = M#message.id,
            lmq_queue:release(Pid, UUID),
            release_messages(Mapping);
        {_Id, {error, _Reason}} ->
            ok
    after 0 ->
        ok
    end.

convert_uuid(UUID) when is_binary(UUID) ->
    uuid:string_to_uuid(binary_to_list(UUID)).

atom_to_binary(Atom) when is_atom(Atom) ->
    list_to_binary(atom_to_list(Atom)).

normalize_props({Props}) ->
    %% jiffy style to proplists
    normalize_props(Props, []).

normalize_props([{<<"pack">>, Duration} | T], Acc) ->
    normalize_props(T, [{pack, round(Duration * 1000)} | Acc]);
normalize_props([{K, V} | T], Acc) ->
    normalize_props(T, [{binary_to_atom(K, latin1), V} | Acc]);
normalize_props([], Acc) ->
    lists:reverse(Acc).

export_props(Props) ->
    export_props(Props, []).

export_props([{pack, Duration} | T], Acc) ->
    export_props(T, [{<<"pack">>, Duration / 1000} | Acc]);

export_props([{K, V} | T], Acc) ->
    export_props(T, [{list_to_binary(atom_to_list(K)), V} | Acc]);

export_props([], Acc) ->
    {lists:reverse(Acc)}.

normalize_default_props(DefaultProps) ->
    normalize_default_props(DefaultProps, []).

normalize_default_props([[Regexp, Props]|T], Acc) when is_binary(Regexp) ->
    normalize_default_props(T, [{Regexp, normalize_props(Props)} | Acc]);

normalize_default_props([], Acc) ->
    lists:reverse(Acc).

export_default_props(DefaultProps) ->
    export_default_props(DefaultProps, []).

export_default_props([{Regexp, Props} | T], Acc) when is_list(Regexp); is_binary(Regexp) ->
    export_default_props(T, [[Regexp, export_props(Props)] | Acc]);

export_default_props([], Acc) ->
    lists:reverse(Acc).

%% ==================================================================
%% EUnit test
%% ==================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

atom_to_binary_test() ->
    ?assertEqual(<<"foo">>, atom_to_binary(foo)).

normalize_props_test() ->
    ?assertEqual(normalize_props({[{<<"retry">>, 3}, {<<"timeout">>, 5.0},
                                  {<<"pack">>, 0.5}]}),
                 [{retry, 3}, {timeout, 5.0}, {pack, 500}]).

export_props_test() ->
    ?assertEqual({[{<<"retry">>, 3}, {<<"timeout">>, 5.0}, {<<"pack">>, 0.5}]},
                 export_props([{retry, 3}, {timeout, 5.0}, {pack, 500}])).

normalize_default_props_test() ->
    ?assertEqual([{<<"lmq">>, [{pack, 1000}]}, {<<"def">>, [{retry, 0}]}],
        normalize_default_props([[<<"lmq">>, {[{<<"pack">>, 1}]}],
                                 [<<"def">>, {[{<<"retry">>, 0}]}]])).

export_default_props_test() ->
    ?assertEqual([[<<"lmq">>, {[{<<"pack">>, 1.0}]}],
                  [<<"def">>, {[{<<"retry">>, 0}]}]],
                 export_default_props([{<<"lmq">>, [{pack, 1000}]},
                                       {<<"def">>, [{retry, 0}]}])).

-endif.
