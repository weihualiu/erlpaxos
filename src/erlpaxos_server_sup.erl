-module(erlpaxos_server_sup).
-author("weihua1986@gmail.com").

-include("erlpaxos.hrl").
-behaviour(supervisor).

-export([start_link/1, start_child/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link(LSock) ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, [LSock]).

start_child() ->
	supervisor:start_child(?SERVER, []).

init([LSock]) ->
	?printlog("erlpaxos_server_sup init ~p~n", [""]),
	Server = {erlpaxos_server_handler, {erlpaxo_server_handler, start_link, [LSock]},
		temporary, brutal_kill, worker, [erlpaxos_server_handler]},
	Children = [Server],
	RestartStrategy = {simple_one_for_one, 0, 1},
	{ok, {RestartStrategy, Children}}.
