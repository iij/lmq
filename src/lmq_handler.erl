-module(lmq_handler).

-behaviour(gen_event).

-export([init/1, handle_event/2, handle_call/2, handle_info/2,
    code_change/3, terminate/2]).

%% ==================================================================
%% gen_event callbacks
%% ==================================================================

init([]) ->
    {ok, []}.

handle_event({_, {new_message, QName}}, State) ->
    io:format("new message arrived: ~p~n", [QName]),
    {ok, State};

handle_event(_, State) ->
    {ok, State}.

handle_call(_, State) ->
    {ok, ok, State}.

handle_info(_, State) ->
    {ok, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
