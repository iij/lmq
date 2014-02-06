-module(lmq_api).

-export([delete/1, push/2, pull/1, pull/2, push_all/2,
    pull_any/1, pull_any/2, done/2, retain/2, release/2,
    update_props/1, update_props/2, set_default_props/1, get_default_props/0,
    normalize_props/1, export_props/1,
    normalize_default_props/1, export_default_props/1]).
-include("lmq.hrl").

delete(Name) when is_binary(Name) ->
    lager:info("lmq_api:delete(~s)", [Name]),
    ok = lmq:delete(Name),
    <<"ok">>.

push(Name, Content) when is_binary(Name) ->
    lager:info("lmq_api:push(~s, ...)", [Name]),
    Bin = msgpack:pack(Content),
    case lmq:push(Name, [{<<"content-type">>,
                          <<"application/x-msgpack">>}], Bin) of
        ok -> <<"ok">>;
        {accum, new} -> <<"packing started">>;
        {accum, yes} -> <<"packed">>
    end.

pull(Name) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s)", [Name]),
    Response = lmq:pull(Name),
    export_message(extract_content_value(Response)).

pull(Name, Timeout) when is_binary(Name) ->
    lager:info("lmq_api:pull(~s, ~p)", [Name, Timeout]),
    {monitors, [{process, Conn}]} = erlang:process_info(self(), monitors),
    case lmq:pull(Name, Timeout, Conn) of
        {error, down} -> ok;
        empty -> <<"empty">>;
        Msg -> export_message(extract_content_value(Msg))
    end.

push_all(Regexp, Content) when is_binary(Regexp) ->
    lager:info("lmq_api:push_all(~s, ...)", [Regexp]),
    case lmq:push_all(Regexp, Content) of
        {ok, _} -> <<"ok">>;
        {error, Reason} -> throw(Reason)
    end.

pull_any(Regexp) ->
    pull_any(Regexp, inifinity).

pull_any(Regexp, Timeout) when is_binary(Regexp) ->
    lager:info("lmq_api:pull_any(~s, ~p)", [Regexp, Timeout]),
    Timeout2 = if
        is_number(Timeout) -> round(Timeout * 1000);
        true -> Timeout
    end,
    {monitors, [{process, Conn}]} = erlang:process_info(self(), monitors),
    case lmq:pull_any(Regexp, Timeout2, Conn) of
        {error, down} -> ok;
        empty -> <<"empty">>;
        Msg -> export_message(extract_content_value(Msg))
    end.

done(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:done(~s, ~s)", [Name, UUID]),
    process_message(ack, Name, UUID).

retain(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:retain(~s, ~s)", [Name, UUID]),
    process_message(keep, Name, UUID).

release(Name, UUID) when is_binary(Name), is_binary(UUID) ->
    lager:info("lmq_api:release(~s, ~s)", [Name, UUID]),
    process_message(abort, Name, UUID).

update_props(Name) when is_binary(Name) ->
    lager:info("lmq_api:update_props(~s)", [Name]),
    lmq:update_props(Name),
    <<"ok">>.

update_props(Name, Props) when is_binary(Name) ->
    lager:info("lmq_api:update_props(~s, ~p)", [Name, Props]),
    case normalize_props(Props) of
        {ok, Props2} ->
            lmq:update_props(Name, to_new_props(Props2)),
            <<"ok">>;
        {error, Reason} ->
            throw(Reason)
    end.

set_default_props(PropsList) ->
    lager:info("lmq_api:set_default_props(~p)", [PropsList]),
    case normalize_default_props(PropsList) of
        {ok, PropsList2} ->
            PropsList3 = [{K, to_new_props(V)} || {K, V} <- PropsList2],
            case lmq:set_default_props(PropsList3) of
                ok -> <<"ok">>;
                Reason -> throw(Reason)
            end;
        {error, Reason} ->
            throw(Reason)
    end.

get_default_props() ->
    lager:info("lmq_api:get_default_props()"),
    Props = [{K, to_old_props(V)} || {K, V} <- lmq:get_default_props()],
    export_default_props(Props).

normalize_props({Props}) ->
    %% jiffy style to proplists
    normalize_props(Props, []).

export_props(Props) ->
    export_props(Props, []).

normalize_default_props(DefaultProps) ->
    normalize_default_props(DefaultProps, []).

export_default_props(DefaultProps) ->
    export_default_props(DefaultProps, []).

%% ==================================================================
%% Private functions
%% ==================================================================

process_message(Fun, Name, UUID) when is_atom(Fun) ->
    case lmq:Fun(Name, UUID) of
        ok -> <<"ok">>;
        {error, Reason} -> throw(Reason)
    end.

export_message(Msg) ->
    export_message(Msg, []).

export_message([{id, V} | Tail], Acc) ->
    export_message(Tail, [{<<"id">>, V} | Acc]);
export_message([{type, compound} | Tail], Acc) ->
    export_message(Tail, [{<<"type">>, <<"package">>} | Acc]);
export_message([{K, V} | Tail], Acc) when is_atom(V) ->
    export_message(Tail, [{atom_to_binary(K, latin1),
                           atom_to_binary(V, latin1)} | Acc]);
export_message([{K, V} | Tail], Acc) when is_atom(K) ->
    export_message(Tail, [{atom_to_binary(K, latin1), V} | Acc]);
export_message([], Acc) ->
    {lists:reverse(Acc)}.

normalize_props([{<<"pack">>, Duration} | T], Acc) when is_number(Duration) ->
    normalize_props(T, [{pack, round(Duration * 1000)} | Acc]);
normalize_props([{<<"accum">>, Duration} | T], Acc) when is_number(Duration) ->
    normalize_props(T, [{accum, round(Duration * 1000)} | Acc]);
normalize_props([{<<"retry">>, N} | T], Acc) when is_integer(N) ->
    normalize_props(T, [{retry, N} | Acc]);
normalize_props([{<<"timeout">>, N} | T], Acc) when is_number(N) ->
    normalize_props(T, [{timeout, N} | Acc]);
normalize_props([{<<"hooks">>, {L}} | T], Acc) when is_list(L) ->
    normalize_props(T, [{hooks, normalize_hooks(L, [])} | Acc]);
normalize_props([], Acc) ->
    {ok, lists:reverse(Acc)};
normalize_props(_, _) ->
    {error, invalid}.

normalize_hooks([], Acc) ->
    lists:reverse(Acc);
normalize_hooks([{Name, L}|T], Acc) when is_binary(Name), is_list(L) ->
    Name2 = binary_to_atom(Name, latin1),
    normalize_hooks(T, [{Name2, normalize_hooks2(L, [])}|Acc]).

normalize_hooks2([], Acc) ->
    lists:reverse(Acc);
normalize_hooks2([[Name, L]|T], Acc) when is_binary(Name), is_list(L) ->
    Name2 = binary_to_existing_atom(Name, latin1),
    normalize_hooks2(T, [{Name2, L}|Acc]).

export_props([{pack, Duration} | T], Acc) ->
    export_props(T, [{<<"pack">>, Duration / 1000} | Acc]);
export_props([{accum, Duration} | T], Acc) ->
    export_props(T, [{<<"accum">>, Duration / 1000} | Acc]);
export_props([{hooks, L} | T], Acc) when is_list(L) ->
    export_props(T, [{<<"hooks">>, export_hooks(L, [])} | Acc]);
export_props([{K, V} | T], Acc) ->
    export_props(T, [{atom_to_binary(K, latin1), V} | Acc]);
export_props([], Acc) ->
    {lists:reverse(Acc)}.

export_hooks([], Acc) ->
    {lists:reverse(Acc)};
export_hooks([{Name, L}|T], Acc) when is_atom(Name), is_list(L) ->
    export_hooks(T, [{atom_to_binary(Name, latin1), export_hooks2(L, [])}|Acc]).

export_hooks2([], Acc) ->
    lists:reverse(Acc);
export_hooks2([{Name, L}|T], Acc) when is_atom(Name), is_list(L) ->
    export_hooks2(T, [[atom_to_binary(Name, latin1), L]|Acc]).

normalize_default_props([[Regexp, Props]|T], Acc) when is_binary(Regexp) ->
    case normalize_props(Props) of
        {ok, Props2} -> normalize_default_props(T, [{Regexp, Props2} | Acc]);
        {error, _}=R -> R
    end;
normalize_default_props([], Acc) ->
    {ok, lists:reverse(Acc)};
normalize_default_props(_, _) ->
    {error, invalid}.

export_default_props([{Regexp, Props} | T], Acc) when is_list(Regexp); is_binary(Regexp) ->
    export_default_props(T, [[Regexp, export_props(Props)] | Acc]);
export_default_props([], Acc) ->
    lists:reverse(Acc).

extract_content_value([QUEUE, ID, {type, normal}=TYPE, {content, {MD, V}}]) ->
    [QUEUE, ID, TYPE, {content, maybe_decode(MD, V)}];
extract_content_value([QUEUE, ID, {type, compound}=TYPE, {content, Content}]) ->
    [QUEUE, ID, TYPE, {content, [maybe_decode(MD, V) || {MD, V} <- Content]}].

maybe_decode(MD, V) ->
    case proplists:get_value(<<"content-type">>, MD) of
        <<"application/x-msgpack">> ->
            {ok, Term} = msgpack:unpack(V),
            Term;
        _ ->
            V
    end.

to_new_props(Props) ->
    lists:keymap(fun(pack) -> accum; (Other) -> Other end, 1, Props).

to_old_props(Props) ->
    lists:keymap(fun(accum) -> pack; (Other) -> Other end, 1, Props).

%% ==================================================================
%% EUnit test
%% ==================================================================

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

normalize_props_test() ->
    ?assertEqual({ok, [{retry, 1}]}, normalize_props({[{<<"retry">>, 1}]})),
    ?assertEqual({ok, [{retry, 2}, {timeout, 5.0}, {pack, 500}]},
                 normalize_props({[{<<"retry">>, 2}, {<<"timeout">>, 5.0},
                                   {<<"pack">>, 0.5}]})),
    ?assertEqual({ok, [{hooks, [{hook_point, [{hook_module, [<<"args1">>, <<"args2">>]}]}]}]},
                 normalize_props({[{<<"hooks">>,
                                    {[{<<"hook_point">>,
                                       [[<<"hook_module">>, [<<"args1">>, <<"args2">>]]]}]}}]})),
    ?assertEqual({error, invalid},
                 normalize_props({[{<<"retry">>, <<"3">>}, {<<"timeout">>, <<"5.0">>},
                                   {<<"pack">>, <<"1">>}]})),
    ?assertEqual({error, invalid}, normalize_props({[{<<"not supported">>, 4}]})).

export_props_test() ->
    ?assertEqual({[{<<"retry">>, 3}, {<<"timeout">>, 5.0}, {<<"pack">>, 0.5}]},
                 export_props([{retry, 3}, {timeout, 5.0}, {pack, 500}])),
    ?assertEqual({[{<<"hooks">>,
                    {[{<<"hook_point">>,
                       [[<<"hook_module">>, [<<"args1">>, <<"args2">>]]]}]}}]},
                 export_props([{hooks, [{hook_point, [{hook_module, [<<"args1">>, <<"args2">>]}]}]}])).

normalize_default_props_test() ->
    ?assertEqual({ok, [{<<"lmq">>, [{pack, 1000}]}, {<<"def">>, [{retry, 0}]}]},
                 normalize_default_props([[<<"lmq">>, {[{<<"pack">>, 1}]}],
                                          [<<"def">>, {[{<<"retry">>, 0}]}]])),
    ?assertEqual({ok, [{<<"lmq">>, [{hooks, [{hook_point, [{hook_module, [<<"args1">>, <<"args2">>]}]}]}]}]},
                 normalize_default_props([[<<"lmq">>,
                                           {[{<<"hooks">>,
                                              {[{<<"hook_point">>,
                                                 [[<<"hook_module">>, [<<"args1">>, <<"args2">>]]]}]}}]}]])),
    ?assertEqual({error, invalid},
                 normalize_default_props([[<<"lmq">>, {[{<<"pack">>, <<"1">>}]}]])),
    ?assertEqual({error, invalid}, normalize_default_props([<<"lmq">>])).

export_default_props_test() ->
    ?assertEqual([[<<"lmq">>, {[{<<"pack">>, 1.0}]}],
                  [<<"def">>, {[{<<"retry">>, 0}]}]],
                 export_default_props([{<<"lmq">>, [{pack, 1000}]},
                                       {<<"def">>, [{retry, 0}]}])),
    ?assertEqual([[<<"lmq">>,
                   {[{<<"hooks">>,
                      {[{<<"hook_point">>,
                         [[<<"hook_module">>, [<<"args1">>, <<"args2">>]]]}]}}]}]],
                export_default_props([{<<"lmq">>,
                                       [{hooks, [{hook_point, [{hook_module, [<<"args1">>, <<"args2">>]}]}]}]}])).

export_message_test() ->
    Ref = make_ref(),
    M = #message{content=Ref},
    UUID = list_to_binary(uuid:uuid_to_string(element(2, M#message.id))),
    ?assertEqual({[{<<"id">>, UUID}, {<<"type">>, <<"normal">>},
                   {<<"content">>, Ref}]},
                 export_message(lmq_lib:export_message(M))),

    M2 = M#message{type=compound},
    ?assertEqual({[{<<"queue">>, <<"test">>}, {<<"id">>, UUID},
                   {<<"type">>, <<"package">>}, {<<"content">>, Ref}]},
                 export_message([{queue, test} | lmq_lib:export_message(M2)])).

props_compatibility_test() ->
    ?assertEqual([{accum, 0}, {retry, 2}, {timeout, 30}],
                 to_new_props([{pack, 0}, {retry, 2}, {timeout, 30}])),
    ?assertEqual([{pack, 0}, {retry, 2}, {timeout, 30}],
                 to_old_props([{accum, 0}, {retry, 2}, {timeout, 30}])).

-endif.
