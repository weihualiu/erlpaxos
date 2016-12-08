-module(erlpaxos_elect).
-author("weihua1986@gmail.com").

-behaviour(gen_server).
-include("erlpaxos.hrl").

% �Զ�ѡ��ģ��
%  ��Բ�ͬ�������ѡ��
%  ��ʱ����cron_service
%  ������̴洢: master�ڵ���Ϣ;��ѡ�˽ڵ���Ϣ
% 

%% ��������
-export([findmaster/0, weight_get/0, heartbeat/0]).
%% ��������
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

% ѯ���Ƿ���master
findmaster() ->
	% ������Ҫ��ڵ������б�
	% [MODULE1, MODULE2]
	% ���ÿ��������ѯ��
	msg_broadcast:block(),
	ok.

% ��ǰ�ڵ��ǲ���master
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

% ѡ�٣���ȡȨ��ֵ
weight_get() ->
	ok.

% �ṩ����Ȩ��ֵ
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
	% �Ƿ�����ѡ��
	% �Ƿ���master
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

