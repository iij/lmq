-module(influxdb_client).

-behaviour(gen_server).

-export([start_link/2, write/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    code_change/3, terminate/2]).

-record(state, {enabled, socket, host, port}).

%% ==================================================================
%% Public API
%% ==================================================================
start_link(Host, Port) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Host, Port}, []).

write(Series) ->
    gen_server:cast(?MODULE, {write, Series}).

%% ==================================================================
%% gen_server callbacks
%% ==================================================================
init({Host, Port}) ->
    case resolve_hostname(Host) of
        {ok, Addr} ->
            {ok, Socket} = gen_udp:open(0, [{active, false}]),
            {ok, #state{enabled=true, socket=Socket, host=Addr, port=Port}};
        _ ->
            {ok, #state{enabled=false}}
    end.

handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast(_, #state{enabled=false}=State) ->
    {noreply, State};
handle_cast({write, Series}, #state{socket=Socket, host=Host, port=Port}=State) ->
    Data = jsonx:encode(Series),
    gen_udp:send(Socket, Host, Port, Data),
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
resolve_hostname(Addr) when is_tuple(Addr) ->
    Addr;
resolve_hostname(Hostname) ->
    case inet:gethostbyname(Hostname) of
        {ok, {_, _, _, _, _, [Addr|_]}} -> {ok, Addr};
        _ -> {error, invalid}
    end.
