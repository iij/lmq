-module(lmq_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2,
    code_change/3, terminate/2]).

%% ==================================================================
%% gen_event callbacks
%% ==================================================================

init([]) ->
    {ok, []}.

handle_event({local, {new_message, _}}, State) ->
    {ok, State};

handle_event({remote, {new_message, QName}}, State) ->
    lager:debug("new message arrived at remote queue ~s", [QName]),
    case lmq_queue_mgr:get(QName) of
        not_found -> ok;
        Pid -> lmq_queue:notify(Pid)
    end,
    {ok, State};

handle_event({local, {queue_created, Name}}, State) ->
    lager:debug("local queue_created ~s", [Name]),
    [lmq_mpull:maybe_pull(Pid, Name) || Pid <- lmq_mpull:list_active()],
    {ok, State};

handle_event({remote, {queue_created, Name}=E}, State) ->
    lager:debug("remote queue_created ~s", [Name]),
    case lmq_queue_mgr:get(Name) of
        not_found ->
            lmq_queue_mgr:get(Name, [create]),
            handle_event({local, E}, State);
        Pid ->
            lmq_queue:reload_properties(Pid),
            {ok, State}
    end;

handle_event({local, {queue_deleted, _}}, State) ->
    {ok, State};

handle_event({remote, {queue_deleted, Name}}, State) ->
    lager:debug("remote queue deleted ~s", [Name]),
    lmq_queue_mgr:delete(Name),
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
