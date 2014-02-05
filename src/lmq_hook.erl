-module(lmq_hook).

%% ==================================================================
%% behaviour definition
%% ==================================================================
-callback init() ->
    {ok | stop, Reason :: term()}.

-callback hooks() ->
    [atom()].

-callback activate([term()]) ->
    {ok, term()}.

-callback deactivate(term()) ->
    ok.

%% ==================================================================
%% hook implementation
%% ==================================================================
%% hook configuration for each queue:
%%   [{hook_name, [{lmq_hook_sample1, [term(), ...]},
%%                 {lmq_hook_sample2, [term(), ...]}]}]
%% hook state for each queue:
%%   [{hook_name, [{lmq_hook_sample1, State},
%%                 {lmq_hook_sample2, State}]}]
-behaviour(gen_server).

-export([start_link/0, stop/0, register/2, call/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-record(state, {loaded_hooks :: list(module()),
                queue_hooks :: dict()
               }).

%% ==================================================================
%% Public API
%% ==================================================================
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE, stop).

register(Queue, Config) when is_atom(Queue) ->
    gen_server:call(?MODULE, {register, Queue, Config}).

call(Queue, Hook, Value) when is_atom(Queue), is_atom(Hook) ->
    gen_server:call(?MODULE, {call, Queue, Hook, Value}).

%% ==================================================================
%% gen_server callbacks
%% ==================================================================
init([]) ->
    {ok, #state{loaded_hooks=[], queue_hooks=dict:new()}}.

handle_call({register, Queue, Config}, _From, #state{loaded_hooks=LoadedHooks,
                                                     queue_hooks=QueueHooks}=State) ->
    try lists:foldl(fun maybe_init_hook/2, LoadedHooks, get_modules(Config)) of
        LoadedHooks2 ->
            Hooks = case dict:find(Queue, QueueHooks) of
                        {ok, V} -> V;
                        error -> []
                    end,
            try update_hooks(Config, Hooks) of
                Hooks2 ->
                    {reply, ok, State#state{loaded_hooks=LoadedHooks2,
                                            queue_hooks=dict:store(Queue, Hooks2, QueueHooks)}}
            catch
                error:function_clause ->
                    {reply, {error, bad_config}, State#state{loaded_hooks=LoadedHooks2}};
                error:not_hookable ->
                    {reply, {error, bad_config}, State#state{loaded_hooks=LoadedHooks2}}
            end
    catch
        error:undef ->
            {reply, {error, bad_hook}, State}
    end;
handle_call({call, Queue, HookName, Value}, _From, #state{queue_hooks=QueueHooks}=State) ->
    Value2 = case dict:find(Queue, QueueHooks) of
                 {ok, Hooks} ->
                     lists:foldl(fun({Module, S}, Acc) ->
                                         try Module:HookName(Acc, S)
                                         catch _:_ -> Acc
                                         end
                                 end, Value, proplists:get_value(HookName, Hooks, []));
                 error ->
                     Value
             end,
    {reply, Value2, State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%% ==================================================================
%% Private functions
%% ==================================================================
get_modules(Config) ->
    lists:foldl(fun({_, Hooks}, Acc) ->
                        Names = proplists:get_keys(Hooks),
                        lists:merge(Acc, lists:sort(Names))
                end, [], Config).

maybe_init_hook(Module, Hooks) ->
    case proplists:is_defined(Module, Hooks) of
        true ->
            Hooks;
        false ->
            ok = Module:init(),
            [Module|Hooks]
    end.

update_hooks([], Acc) ->
    Acc;
update_hooks([{HookName, Modules}|T], Acc) ->
    Creater = fun({Module, Args}) ->
                      case lists:member(HookName, Module:hooks()) of
                          true ->
                              {ok, State} = Module:activate(Args),
                              {Module, State};
                          false ->
                              erlang:error(not_hookable)
                      end
              end,
    Remover = fun({Module, State}) -> catch Module:deactivate(State) end,
    Hooks = proplists:get_value(HookName, Acc, []),
    Hooks2 = sort_same_order(Hooks, Modules, Creater, Remover),
    update_hooks(T, lists:keystore(HookName, 1, Acc, {HookName, Hooks2})).

sort_same_order(List, Guide, Creater, Remover) ->
    sort_same_order(List, Guide, [], Creater, Remover).

sort_same_order([], [], Acc, _, _) ->
    lists:reverse(Acc);
sort_same_order(List, [], Acc, Creater, Remover) ->
    lists:foreach(Remover, List),
    sort_same_order([], [], Acc, Creater, Remover);
sort_same_order([], Guide, Acc, Creater, Remover) ->
    Acc2 =lists:foldl(fun(E, A) -> [Creater(E)|A] end, Acc, Guide),
    sort_same_order([], [], Acc2, Creater, Remover);
sort_same_order([{Key, _}=E|List], [{Key, _}|Guide], Acc, Creater, Remover) ->
    sort_same_order(List, Guide, [E|Acc], Creater, Remover);
sort_same_order(List, [{Key, _}=E|Guide], Acc, Creater, Remover) ->
    case proplists:get_value(Key, List) of
        undefined ->
            sort_same_order(List, Guide, [Creater(E)|Acc], Creater, Remover);
        Other ->
            List2 = proplists:delete(Key, List),
            sort_same_order(List2, Guide, [{Key, Other}|Acc], Creater, Remover)
    end.

%% ==================================================================
%% EUnit test
%% ==================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

sort_same_order_test_() ->
    C = fun({K, [E]}) -> {K, E} end,
    R = fun(_) -> ok end,
    [?_assertEqual([{a, 1}, {b, 2}], sort_same_order([], [{a, [1]}, {b, [2]}], C, R)),
     ?_assertEqual([{b, 2}], sort_same_order([{a, 1}, {b, 2}, {c, 3}], [{b, [2]}], C, R)),
     ?_assertEqual([{c, 3}, {d, 4}, {a, 1}],
                   sort_same_order([{a, 1}, {b, 2}, {c, 3}], [{c, [3]}, {d, [4]}, {a, [1]}], C, R))].

-endif.
