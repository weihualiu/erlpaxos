-module(erlpaxos_elect).
-author("weihua1986@gmail.com").

-behaviour(gen_server).
-include("erlpaxos.hrl").

% 自动选举模块
%  针对不同服务进行选举
%  定时采用cron_service
%  服务进程存储: master节点信息;候选人节点信息
% 

%% 主动调用
-export([findmaster/0, weight_get/0, heartbeat/0]).
%% 被动调用
-export([ismaster/0, weight_self/0]).

-export([start/0, start_link/0]).
%%callback
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-ifdef(ewp_debug_flag).
-compile(export_all).
-endif.

register() ->
	% node_add function
	
	ok.

node_add() ->
	ok.

node_del() ->
	ok.

% 询问是否是master
findmaster() ->
	% 遍历需要多节点服务的列表
	% [MODULE1, MODULE2]
	% 针对每个服务发起询问
	msg_broadcast:block(),
	ok.

% 当前节点是不是master
ismaster() ->
	try
		case gen_server:call(?MODULE, master) of
			undefined ->
				<<"false">>;
			Info ->
				<<"true">>
		end
	catch
		_:ErrM ->
			?printerr("ismaster get message failed! ~p~n",[ErrM]),
			<<"error">>
	end.

% 选举，获取权重值
weight_get() ->
	ok.

% 提供自身权重值
weight_self() ->
	ok.

heartbeat() ->
	?printlog("hearbeat ~p~n", [""]),
	Bin = <<"master_select$ismaster$$">>,
	%R = msg_broadcast:block(Bin),
	% parse result
	% find no active node
	%findErr(R),
	% clear exception nodes
	%nodesUpdate([]),
	% 是否正在选举
	% 是否有master
	% 
	ok.

start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
	gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

%% ====================================================================
%% Server functions
%% ====================================================================
init(_Args) ->
	process_flag(trap_exit, true),
	Crons = [{'*', '*', '*', '*', '*', {erlpaxos_elect, heartbeat, []}}],
	erlpaxos_cron_service:load_task_from_list(Crons),
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

%%#####################private function########################################
% nodes.conf
nodesUpdate(L) when is_binary(L) ->
	CfgPath = filename:join(ewp_file_util:get_config_dir(), "nodes.conf"),
	case file:write_file(CfgPath, L) of
		ok ->
			true;
		{error, Reason} ->
			?printerr("nodes update failed! ~p~n", [Reason]),
			false
	end;
nodesUpdate(L) ->
	nodesUpdate(list_to_binary(L)).

getNodes() ->
	CfgPath = filename:join(ewp_file_util:get_config_dir(), "nodes.conf"),
	{ok, Bin} = file:consult(CfgPath),
	Bin.


find([]) ->
	false;
find([{_, <<"true">>}|_T]) ->
	true;
find([{_, _}|T]) ->
	find(T).

findErr(L) ->
	findErr(L, []).

findErr([], R) ->
	R;
findErr([{Host, <<"error">>}|T], R) ->
	findErr(T, R ++ Host);
findErr([{_, _}|T], R) ->
	findErr(T, R).

