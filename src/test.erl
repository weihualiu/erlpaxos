-module(test).
-author("weihua1986@gmail.com").

-include("erlpaxos.hrl").

-compile(export_all).

show() ->
	?printlog("show executable!~p~n", [""]),
	ok.

verbose() ->
	?printlog("verbose executable! ~p~n", ["oh! mygod!"]),
	ok.
