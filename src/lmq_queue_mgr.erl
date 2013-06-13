-module(lmq_queue_mgr).

-behaviour(gen_server).
-export([start_link/1, create/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-define(SPEC, {lmq_queue_sup,
               {lmq_queue_sup, start_link, []},
               permanent, 10000,
               supervisor, [lmq_queue_sup]}).

-record(state, {sup}).

start_link(Sup) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Sup], []).

create(Name) when is_list(Name) ->
    create(list_to_atom(Name));
create(Name) when is_atom(Name) ->
    gen_server:call(?MODULE, {create, Name}).

init([Sup]) ->
    %% start queue supervisor later in order to avoid deadlock
    self() ! {start_queue_supervisor, Sup},
    {ok, #state{}}.

handle_call({create, Name}, _From, S=#state{}) ->
    ok = lmq_lib:create(Name),
    R = supervisor:start_child(S#state.sup, [Name]),
    {reply, R, S}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info({start_queue_supervisor, Sup}, S=#state{}) ->
    {ok, Pid} = supervisor:start_child(Sup, ?SPEC),
    {noreply, S#state{sup=Pid}};
handle_info(Msg, State) ->
    io:format("Unknown message: ~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
