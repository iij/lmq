-module(lmq).

-include("lmq.hrl").
-export([start/0, stop/0]).
-export([push/2]).

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
    Pid = lmq_queue_mgr:find(Name, [create]),
    lmq_queue:push(Pid, Content).

%% ==================================================================
%% Private functions
%% ==================================================================

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.
