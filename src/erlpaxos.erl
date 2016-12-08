-module(erlpaxos).
-author("weihua1986@gmail.com").

-include("erlpaxos.hrl").
-behaviour(application).

-export([start/0, start/2, stop/1]).

start() ->
	application:start(erlpaxos).

start(_Type, StartArgs) ->
	?printmsg("erlpaxos app start ~p~n", [""]),
	% network
	%inets:start(),
	case erlpaxos_sup:start_link(StartArgs) of
		{ok, Pid} ->
			{ok, Pid};
		Error ->
			Error
	end.

stop(_State) ->
	ok.
