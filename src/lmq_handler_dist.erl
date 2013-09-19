-module(lmq_handler_dist).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2,
    code_change/3, terminate/2]).

-record(state, {nodes}).

%% ==================================================================
%% gen_event callbacks
%% ==================================================================

init([Nodes]) ->
    broadcast(Nodes, {join_node, node()}),
    {ok, #state{nodes=Nodes}}.

handle_event({remote, {join_node, Node}}, #state{nodes=Nodes}=S) ->
    case lists:member(Node, Nodes) of
        true -> {ok, S};
        false -> {ok, S#state{nodes=[Node | Nodes]}}
    end;

handle_event({remote, _Event}, State) ->
    {ok, State};

handle_event({local, Event}, State) ->
    broadcast(State#state.nodes, Event),
    {ok, State};

handle_event(_Event, State) ->
    {ok, State}.

handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%% ==================================================================
%% Private functions
%% ==================================================================

broadcast(Nodes, Event) ->
    [lmq_event:notify_remote(Node, Event) || Node <- Nodes],
    ok.
