-module(lmq_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2,
    code_change/3, terminate/2]).

%% ==================================================================
%% gen_event callbacks
%% ==================================================================

init([]) ->
    {ok, []}.

handle_event({remote, {new_message, QName}}, State) ->
    lager:debug("new message arrived at remote queue ~s", [QName]),
    case lmq_queue_mgr:get(QName) of
        not_found -> ok;
        Pid -> lmq_queue:notify(Pid)
    end,
    {ok, State};

handle_event(Event, State) ->
    lager:warning("Unknown event received: ~p", [Event]),
    {ok, State}.

handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
