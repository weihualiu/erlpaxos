-module(erlpaxos_server_handler).
-author("weihua1986@gmail.com").

-include("erlpaxos.hrl").
-behaviour(gen_server).

-export([start_link/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {lsock, socket, addr}).

start_link(LSock) ->
	?printlog("erlpaxos_server_handler start_link ~p~n", [""]),
	gen_server:start_link(?MODULE, [LSock], []).

init([Socket]) ->
	?printlog("erlpaxos_server_handler init ~p~n", [""]),
	inet:setopts(Socket, [{active, once}, {packet, 2}, binary]),
	{ok, #state{lsock = Socket}, 0}.

handle_call(Msg, _From, State) ->
	{reply, {ok, Msg}, State}.

handle_cast(stop, State) ->
	{stop, normal, State}.

handle_info({tcp, Socket, Data}, State) ->
	inet:setopts(Socket, [{active, once}]),
	?printlog("receive message from client ~p~n", [Data]),
	ok = gen_tcp:send(Socket, ">"),
	{noreply, State};
handle_info({tcp_closed, _}, #state{addr = Addr} = StateData) ->
	?printlog("client disconnect ~p~n", [self(), Addr]),
	{stop, normal, StateData};
handle_info(timeout, #state{lsock = LSock} = State) ->
	{ok, ClientSocket} = gen_tcp:accept(LSock),
	{ok, {IP, _Port}} = inet:peername(ClientSocket),
	erlpaxos_server_sup:start_child(),
	{noreply, State#state{socket = ClientSocket, addr = IP}};
handle_info(_Info, StateData) ->
	{noreply, StateData}.

terminate(_Reason, #state{socket = Socket}) ->
	(catch gen_tcp:close(Socket)),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
