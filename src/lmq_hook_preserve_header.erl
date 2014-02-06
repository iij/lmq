-module(lmq_hook_preserve_header).
-behaviour(lmq_hook).

-export([init/0, hooks/0, activate/1, deactivate/1]).
-export([pre_http_push/2]).

init() ->
    ok.

hooks() ->
    [pre_http_push].

activate(Preserve) ->
    {ok, Preserve}.

deactivate(_) ->
    ok.

pre_http_push({MD, Content, Req}, Preserve) ->
    {Hdrs, Req2} = cowboy_req:headers(Req),
    MD2 = lists:foldl(fun(K, Acc) ->
                              case proplists:get_value(K, Hdrs) of
                                  undefined -> Acc;
                                  V -> lists:keystore(K, 1, Acc, {K, V})
                              end
                      end, MD, Preserve),
    {MD2, Content, Req2}.

%% ==================================================================
%% EUnit test
%% ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

hooks_test_() ->
    [?_assertEqual([pre_http_push], hooks())].

activate_test_() ->
    [?_assertEqual({ok, [<<"header1">>]}, activate([<<"header1">>]))].

deactivate_test_() ->
    [?_assertEqual(ok, deactivate([<<"header1">>]))].

pre_http_push_test_() ->
    Hdrs = [{<<"content-type">>, <<"text/plain">>},
            {<<"x-custom-header">>, <<"foo">>},
            {<<"x-dummy-header">>, <<"dummy">>}],
    Req = cowboy_req:new([], [], undefined, <<"POST">>, <<"/messages/test">>, <<"">>,
                         <<"HTTP/1.1">>, Hdrs, undefined, undefined, <<"">>, false, false, undefined),
    MD = [{<<"content-type">>, <<"application/octet-stream">>}],
    Body = <<"body">>,
    [?_assertEqual({[{<<"content-type">>, <<"application/octet-stream">>},
                     {<<"x-custom-header">>, <<"foo">>}],
                    Body, Req},
                   pre_http_push({MD, Body, Req}, [<<"x-custom-header">>])),
     ?_assertEqual({[{<<"content-type">>, <<"text/plain">>},
                     {<<"x-custom-header">>, <<"foo">>}],
                    Body, Req},
                   pre_http_push({MD, Body, Req}, [<<"content-type">>, <<"x-custom-header">>]))].

-endif.
