-module(erlpaxos_broadcast).
-author("weihua1986@gmail.com").

-behaviour(gen_server).
-include("erlpaxos.hrl").

% 消息广播模块

-export([block/1, noblock/1]).

-export([start_link/0, start/0]).

%% gen_server callback
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-ifdef(ewp_debug_flag).
-compile(export_all).
-endif.

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
	gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

% 阻塞方式广播
% 返回数据 [error, ..., ...]
block(Data) when is_binary(Data) ->
	Remotes = getNodes(),
	case erlang:length(Remotes) of
		0 ->
			[];
		_ ->
			lists:foldr(fun({Host, Port}, Acc) ->
				[{Host, Port, request(tcp, {Host, Port}, Data)}] ++ Acc
			end, [], Remotes)
	end;
block(Data) ->
	block(list_to_binary(Data)).

	
% 非阻塞方式广播
% 无返回数据
noblock(Data) when is_binary(Data) ->
	Remotes = getNodes(),
	case erlang:length(Remotes) of
		0 ->
			ok;
		_ ->
			% 大量节点有阻塞情况，改用独立进程处理
			spawn(fun() -> 
				lists:foreach(fun({Host, Port}) ->
					% 错误返回
					request(tcp, {Host, Port}, Data)
				end, Remotes)
			end)
	end,
	ok;
noblock(Data) ->
	noblock(list_to_binary(Data)).
	
%%################gen_server callback################################
init(_Args) ->
	process_flag(trap_exit, true),
	% 
	{ok, []}.

handle_call(master, _Request, State) ->
	R = get("master"),
	{reply, R, State};
handle_call(_Msg, _Request, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(Reason, _State) ->
	?printmsg("logprocess exit: ~p~n", [Reason]),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
%%################private function##########################
getNodes() ->
	%ewp_conf_util:get_app_conf_value("nodes", Key, []).
	% [{"182.207.129.1",4001,tcp},{"182.207.129.2",4001,tcp}]
	CfgPath = filename:join(ewp_file_util:get_config_dir(), "nodes.conf"),
	{ok, Bin} = file:consult(CfgPath),
	Bin.

request(tcp, {Host,Port}, Data) when is_binary(Data) ->
	try
		{ok, Sock} = gen_tcp:connect(Host, Port, [binary, {packet, 0}]),
		ok = gen_tcp:send(Sock, Data),
		Res = gen_tcp:recv(Sock,0),
		ok = gen_tcp:close(Sock),
		case Res of
			{ok, Bin} ->
				Bin;
			{error, Reson} ->
				<<"error">>
		end
	catch
		_:ErrMsg ->
			<<"error">>
	end;
request(http, {Host,Port}, Data) when is_binary(Data) ->
	try
		ContentType = "application/x-www-form-urlencoded;charset=utf-8",
		Post = {lists:concat(["http://", Host,":",Port, "/cnc/hb"]), [], ContentType, Data},
		case httpc:request(post, Post, [{timeout, 500}], []) of
			{ok, {{_, 200, _}, _Headers, Res}} ->
				case Res of
					[] ->
						?printerr("message broadcast failed! remote host:~p, message body is null~n", [Host]),
						[];
					_ ->
						?printmsg("message broadcast Response:~p~n", [Res]),
						Res
				end;
			{ok, {{_, _StatusCode, _}, _ResHeaders, _ResBody}} ->
				?printerr("message broadcast failed! remote host:~p, message body:~p~n", [Host,_ResBody]),
				<<"error">>;
			 Other ->
				?printerr("message broadcast failed! remote host:~p, message body:~p~n", [Host,Other]),
				<<"error">>
		end
	catch
		_:ErrMsg ->
			?printerr("message broadcast failed! remote host:~p, message body:~p~n", [Host,ErrMsg]),
			<<"error">>
	end;
request(_, _, _) ->
	<<"error">>.
