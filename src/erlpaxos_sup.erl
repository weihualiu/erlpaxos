-module(erlpaxos_sup).
-author("weihua1986@gmail.com").

-behaviour(supervisor).
-include("erlpaxos.hrl").

-export([start_link/1, init/1]).


start_link(_) ->
	?printmsg("erlpaxos app start link ~p~n", [""]),
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Opts = [binary, {packet, 2}, {reuseaddr, true}, {keepalive, true}, {backlog, 30}, {active, false}],
	% read base.conf
	ListenPort = 8201,
	{ok ,LSock} = gen_tcp:listen(ListenPort, Opts),
	Servers = [erlpaxos_elect, erlpaxos_broadcast, {erlpaxos_server_sup, LSock}, erlpaxos_cron_service],
	ServerConfs =
	lists:foldl(fun({Server, Args}, Acc) ->
		[server_tuple(Server, Args) | Acc];
		(Server, Acc) ->
		[server_tuple(Server) | Acc]
		end, [], Servers),
	?printlog("ServerConfs is ~p~n", [ServerConfs]),
	{ok, {{one_for_one, 10, 3600}, ServerConfs}}.

server_tuple(Server) ->
	{Server, {Server, start_link, []},
		permanent,
		2000,
		worker,
		[Server]}.

server_tuple(Server, Args) ->
	{Server, {Server, start_link, [Args]},
		permanent,
		2000,
		worker,
		[Server]}.
