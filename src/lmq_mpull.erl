-module(lmq_mpull).

-behaviour(gen_fsm).

-include("lmq.hrl").

-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
    terminate/3, code_change/4,
    idle/2, idle/3, waiting/2, finalize/2]).
-export([start/0, start_link/0, pull/2, pull/3, maybe_pull/2, list_active/0]).

-define(UNEXPECTED(Event, State),
    lager:warning("~p received unknown event ~p while in state ~p",
        [self(), Event, State])).
-define(CLOSE_WAIT, 10).

-record(state, {from, monitor, regexp, timeout, mapping}).

%% ==================================================================
%% Public API
%% ==================================================================

start() ->
    supervisor:start_child(lmq_mpull_sup, []).

start_link() ->
    gen_fsm:start_link(?MODULE, [], []).

pull(Pid, Regexp) ->
    gen_fsm:sync_send_event(Pid, {pull, Regexp, infinity}, infinity).

pull(Pid, Regexp, Timeout) ->
    gen_fsm:sync_send_event(Pid, {pull, Regexp, Timeout}, infinity).

maybe_pull(Pid, QName) when is_atom(QName) ->
    gen_fsm:send_event(Pid, {maybe_pull, QName}).

list_active() ->
    [Pid || {_, Pid, _, _} <- supervisor:which_children(lmq_mpull_sup)].

%% ==================================================================
%% gen_fsm callbacks
%% ==================================================================

init([]) ->
    {ok, idle, #state{}}.

idle(Event, State) ->
    ?UNEXPECTED(Event, idle),
    {next_state, idle, State}.

idle({pull, Regexp, Timeout}, {Pid, _}=From, #state{}=S) ->
    Monitor = erlang:monitor(process, Pid),
    case lmq_queue_mgr:match(Regexp) of
        {error, _}=R ->
            {stop, error, R, S#state{from=From, monitor=Monitor}};
        Queues ->
            Mapping = lists:foldl(fun({_, QPid}=Q, Acc) ->
                Id = lmq_queue:pull_async(QPid, Timeout),
                dict:store(Id, Q, Acc)
            end, dict:new(), Queues),
            if is_number(Timeout), Timeout > 0 ->
                gen_fsm:send_event_after(Timeout, cancel);
                true -> ok
            end,
            State = S#state{from=From, monitor=Monitor, regexp=Regexp,
                            timeout=Timeout, mapping=Mapping},
            {next_state, waiting, State}
    end;

idle(Event, _From, State) ->
    ?UNEXPECTED(Event, idle),
    {next_state, idle, State}.

waiting({maybe_pull, QName}, #state{}=S) ->
    State = case re:compile(S#state.regexp) of
        {ok, MP} ->
            case re:run(atom_to_list(QName), MP) of
                {match, _} ->
                    case lmq_queue_mgr:get(QName) of
                        not_found -> S;
                        Pid ->
                            Id = lmq_queue:pull_async(Pid, S#state.timeout),
                            Mapping = dict:store(Id, {QName, Pid}, S#state.mapping),
                            S#state{mapping=Mapping}
                    end;
                _ -> S
            end;
        {error, _} -> S
    end,
    {next_state, waiting, State};

waiting(cancel, #state{}=S) ->
    waiting(timeout, S);

waiting(timeout, #state{}=S) ->
    cancel_pull(S#state.mapping),
    gen_fsm:reply(S#state.from, empty),
    {next_state, finalize, S, ?CLOSE_WAIT};

waiting(Event, State) ->
    ?UNEXPECTED(Event, waiting),
    {next_state, waiting, State}.

finalize(timeout, State) ->
    {stop, normal, State};

finalize(Event, State) ->
    ?UNEXPECTED(Event, finalize),
    {next_state, finalize, State}.

handle_info({Id, #message{}=M}, waiting, #state{mapping=Mapping}=S) ->
    {Name, _} = dict:fetch(Id, Mapping),
    cancel_pull(dict:erase(Id, Mapping)),
    Response = lmq_lib:export_message(M),
    gen_fsm:reply(S#state.from, [{queue, Name} | Response]),
    {next_state, finalize, S, ?CLOSE_WAIT};

handle_info({Id, {error, Reason}}, waiting, #state{mapping=Mapping}=S) ->
    Mapping1 = dict:erase(Id, Mapping),
    lager:debug("pull_any for ~p: ~p, rest ~p",
        [element(1, dict:fetch(Id, Mapping)), Reason, dict:size(Mapping1)]),
    case dict:size(Mapping1) of
        0 ->
            gen_fsm:reply(S#state.from, empty),
            %% it is safe to shutdown because all responses are received.
            {stop, normal, S};
        _ ->
            %% short period for procces messages that already in the mailbox.
            {next_state, waiting, S#state{mapping=Mapping1}, ?CLOSE_WAIT}
    end;

handle_info({Id, #message{id={_, UUID}}}, finalize, #state{}=S) ->
    {_, Pid} = dict:fetch(Id, S#state.mapping),
    lmq_queue:release(Pid, UUID),
    {next_state, finalize, S, ?CLOSE_WAIT};

handle_info({_Id, {error, _Reason}}, finalize, State) ->
    {next_state, finalize, State, ?CLOSE_WAIT};

handle_info({'DOWN', Monitor, process, _, _}, _, #state{monitor=Monitor}=S) ->
    cancel_pull(S#state.mapping),
    {next_state, finalize, S, ?CLOSE_WAIT};

handle_info(Event, StateName, State) ->
    ?UNEXPECTED(Event, StateName),
    {next_state, StateName, State}.

handle_event(Event, StateName, State) ->
    ?UNEXPECTED(Event, StateName),
    {next_state, StateName, State}.

handle_sync_event(Event, _From, StateName, State) ->
    ?UNEXPECTED(Event, StateName),
    {reply, error, StateName, State}.

terminate(normal, _StateName, #state{monitor=Monitor}) ->
    erlang:demonitor(Monitor, [flush]),
    ok;

terminate(error, _StateName, #state{monitor=Monitor}) ->
    erlang:demonitor(Monitor, [flush]),
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% ==================================================================
%% Private functions
%% ==================================================================

cancel_pull(Mapping) ->
    %% after calling this function, queues never sent a new message.
    dict:map(fun(Id, {_, Pid}) -> lmq_queue:pull_cancel(Pid, Id) end, Mapping).
