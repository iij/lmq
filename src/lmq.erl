-module(lmq).

-include("lmq.hrl").
-export([start/0, stop/0]).
-export([push/2, pull/1, pull/2, update_props/1, update_props/2,
    set_default_props/1, get_default_props/0]).

-define(DEPS, [lager, crypto, quickrand, uuid, msgpack, msgpack_rpc,
    mnesia, ranch, lmq]).

%% ==================================================================
%% Public API
%% ==================================================================

start() ->
    [ensure_started(Dep) || Dep <- ?DEPS],
    lager:set_loglevel(lager_console_backend, debug).

stop() ->
    [application:stop(Dep) || Dep <- lists:reverse(?DEPS)],
    ok.

push(Name, Content) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    lmq_queue:push(Pid, Content).

pull(Name) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    Msg = lmq_queue:pull(Pid),
    lmq_lib:export_message(Msg).

pull(Name, Timeout) when is_atom(Name) ->
    Pid = lmq_queue_mgr:get(Name, [create]),
    case lmq_queue:pull(Pid, Timeout) of
        empty -> <<"empty">>;
        Msg -> lmq_lib:export_message(Msg)
    end.

update_props(Name) when is_atom(Name) ->
    update_props(Name, []).

update_props(Name, Props) when is_atom(Name) ->
    lmq_queue_mgr:get(Name, [create, update, {props, Props}]).

set_default_props(Props) ->
    lmq_queue_mgr:set_default_props(Props).

get_default_props() ->
    lmq_queue_mgr:get_default_props().

%% ==================================================================
%% Private functions
%% ==================================================================

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.
