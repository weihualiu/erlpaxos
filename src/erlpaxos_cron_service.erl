-module(erlpaxos_cron_service).
-author("weihua1986@gmail.com").

%% HOWTO
%%   If you want to use cron_service, you should:
%%     use one of these three methods to load your tasks;
%%        a.cron_service:load_from_file(FilePath).
%%        b.cron_service:load_from_list(TaskList).
%%        c.cron_service:load_task([#task{}]).
%%
%%   When using load_from_file/1 or load_from_list/1 to load tasks, a certain
%%   task term is a tuple with six or seven fields.
%%   eg:
%%     {Minute, Hour, Day_Of_The_Month, Month, Day_Of_The_Week, MFA}
%%     {Minute, Hour, Day_Of_The_Month, Month, Day_Of_The_Week, MFA, Options}
%%   The first five fields are schedule time fields and the sixth is the
%%   function to be executed, The last optional field is extra options.
%%
%%   Here are the first five fields and their allowed values:
%%     Field          Values
%%     ---------------------
%%     Minute           0-59
%%     Hour             0-23
%%     Day of the Month 1-31
%%     Month            1-12
%%     Day of the Week  1-8
%%   Each of the above values can also contain ranges(eg:1-27), lists(eg:[1,3]),
%%   and step(eg:1-59/15) values.
%%   If a field contains an asterisk (*), it tells cron_service to accept all
%%   allowed values.
%%
%%   The MFA field is a mfa tuple:
%%     {Module, Function, Arg}
%%
%%   The Options field is optional, and it has the following types:
%%     Options = [Option]
%%     Option = {name, TaskName} | {interval, IntervalMinutes}
%%              | {start, StartAfter} | {finish, FinishBefore}
%%              | {max, MaxExecTimes} | {persistent, Bool}
%%     TaskName = any()
%%     IntervalMinutes, MaxExecTimes = int()
%%     StartAfter, FinishBefore = {date(), time()}
%%     Bool = true | false
%%   When the interval option is given, the start option should also be given.
%%   The meanings of these options are contained in #task{} definition.
%%
%%
%% EXAMPLE
%%   See also load_list_test/0, load_record_test/0
%%

-behaviour(gen_server).

-include("erlpaxos.hrl").


%% External exports
-export([
    %% Start
    start_link/0, exec/0, % Not for public use

    %% list, load, select, cancel, delete and restart task
    list/0, load_task/1, load_task_from_file/1,
    load_task_from_list/1, select_by_name/1,
    cancel_task/1, delete_task/1, restart_task/1]).

%% gen_server callbacks
-export([init/1, handle_call/3,
         handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% for test use
-export([dosth/1]).

-define(SERVER, ?MODULE).
-define(CRONTAB, erlpaxos_crontab).
-define(Interval_S, 20). % Interval seconds of checking tasks

-record(state, {last_minute}).


%% ====================================================================
%% External functions
%% ====================================================================

%%--------------------------------------------------------------------
%% @doc
%%  启动服务
%%
%% @spec start_link() -> ok
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%%  列出当前管理的所有任务
%%
%% @spec list() -> [{Key::string(), Task::task()}]
%% @end
%%--------------------------------------------------------------------
%%@ list all tasks
list() ->
    safe_call(list).

%%--------------------------------------------------------------------
%% @doc
%%  加载一个任务
%%
%% @spec load_task(Task::task()|list()) -> ok
%% @end
%%--------------------------------------------------------------------
%% load tasks from record #task
load_task(Task) when is_record(Task, task) ->
    load_task([Task]);
load_task(Tasks) when is_list(Tasks) ->
    safe_call({load_task, Tasks}).

%%--------------------------------------------------------------------
%% @doc
%%  从文件中加载任务
%%
%% @spec load_task_from_file(FilePath::string()) -> ok
%% @end
%%--------------------------------------------------------------------
%% load tasks from file
load_task_from_file(FilePath) when is_list(FilePath) ->
    case file:consult(FilePath) of
        {ok, Confs} ->
            load_task_from_list(Confs);
        {error, Reason} ->
            ?printlog("failed to load tasks from file: ~p, for: ~p~n", [FilePath, Reason]),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%%  从list中加载任务
%%
%% @spec load_task_from_list(Task::list()) -> ok
%% @end
%%--------------------------------------------------------------------
%% load tasks from list
load_task_from_list(List) when is_list(List) ->
    Tasks = [parse_task(X) || X <- List],
    load_task(Tasks).

%%--------------------------------------------------------------------
%% @doc
%%  取消一个任务
%%
%% @spec cancel_task(Key::string()) -> ok
%% @end
%%--------------------------------------------------------------------
cancel_task(Key) ->
    safe_call({update_status, Key, cancel}).

%%--------------------------------------------------------------------
%% @doc
%%  重启一个已停止的任务
%%
%% @spec restart_task(Key::string()) -> ok
%% @end
%%--------------------------------------------------------------------
restart_task(Key) ->
    safe_call({update_status, Key, ready}).

%%--------------------------------------------------------------------
%% @doc
%%  删除一个任务
%%
%% @spec delete_task(Key::string()) -> ok
%% @end
%%--------------------------------------------------------------------
delete_task(Key) ->
    safe_call({delete_task, Key}).

%%--------------------------------------------------------------------
%% @doc
%%  按名称查询任务
%%
%% @spec select_by_name(Name::any()) -> ok
%% @end
%%--------------------------------------------------------------------
select_by_name(Name) ->
    check_server_running(),
    {ok, [{Key, Task} || {Key, Task} <- ets:tab2list(?CRONTAB), Task#task.name==Name]}.

%% @private
%% execute task
exec() ->
    Datetime = calendar:local_time(),
    gen_server:cast(?MODULE, {exec, Datetime}).

%% ====================================================================
%% gen_server callbacks
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
%% @hidden
init([]) ->
    process_flag(trap_exit, true),
    ets:new(?CRONTAB, [named_table, set, protected]),
    timer:apply_interval(timer:seconds(?Interval_S), ?MODULE, exec, []),
    {ok, #state{}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
%% @hidden
handle_call(list, _From, State) ->
    {reply, ets:tab2list(?CRONTAB), State};
handle_call({load_task, Tasks}, _From, State) ->
    TimeStamp = calendar:local_time(),
    lists:foreach(
        fun(Task) when is_record(Task, task) ->
                ets:insert(?CRONTAB, {keygen(), Task#task{
                            created_at  = TimeStamp,
                            exec_times  = 0,
                            status      = ready}});
           (Other) ->
                ?printlog("ignored task: ~p~n", [Other])
        end, Tasks),
    {reply, ok, State};
handle_call({update_status, Key, NewStatus}, _From, State) ->
    Reply = 
        case ets:lookup(?CRONTAB, Key) of
            [{Key, Task}] ->
                ets:insert(?CRONTAB, {Key, Task#task{status = NewStatus}}),
                ok;
            _ ->
                {error, task_not_found}
        end,
    {reply, Reply, State};
handle_call({delete_task, Key}, _From, State) ->
    Reply = 
        case ets:lookup(?CRONTAB, Key) of
            [] ->
                {error, task_not_found};
            _ ->
                ets:delete(?CRONTAB, Key),
                ok
        end,
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%% @hidden
handle_cast({exec, DateTime}, #state{last_minute = LastMinute} = State) ->
    {{Y, Mo, D}, {H, Mi, _}} = DateTime,
    if LastMinute /= Mi ->
            Week = calendar:day_of_the_week({Y, Mo, D}),
            NowSecs = calendar:datetime_to_gregorian_seconds(datetime()),
            Tasks = [{K, Task} || {K, Task} <-ets:tab2list(?CRONTAB), Task#task.status == ready],
            execute_task(Tasks, {Mi, H, D, Mo, Week, NowSecs}),
            {noreply, State#state{last_minute = Mi}};
        true ->
            {noreply, State}
    end;
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
%% @hidden
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
%% @hidden
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
%% @hidden
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

%%check the time and execute task
execute_task([], _Now) ->
    ignore;
execute_task([{Key, Task} | Rest], Now) ->
    CheckFlag = check_time(Key, Task, Now),
    process(Key, Task, Now, CheckFlag),
    execute_task(Rest, Now).

check_time(Key, #task{next_exec_at = NextTime,
                      start_after = StartTime,
                      finish_before = FinishTime} = Task,
            {Mi, H, D, Mo, W, NowSecs}) ->
    try
        case StartTime of
            undefined ->
                go_on;
            _ when StartTime > NowSecs ->
                throw(etime);
            _ ->
                go_on
        end,
        case FinishTime of
            undefined ->
                go_on;
            _ when FinishTime < NowSecs ->
                update_task(Key, Task#task{status = finish}),
                throw(etime);
            _ ->
                go_on
        end,
        case NextTime of
            {normal, {Mi0, H0, D0, Mo0, W0}} ->
                check_time_1([{W0, W}, {Mo0, Mo}, {D0, D},{H0, H}, {Mi0, Mi}], true);
            {interval, {Secs, _Interval}} ->
                SecList = lists:seq((Secs - ?Interval_S), (Secs + ?Interval_S)),
                check_time_1([{SecList, NowSecs}], true)
        end
    catch
        throw:etime ->
            false;
        Type:Why->
            ?printlog("failed to check time, ~p:~p~n", [Type, Why]),
            throw("failed to check time")
    end.

check_time_1([], CheckFlag) ->
    CheckFlag;
check_time_1(_CheckList, false) ->
    false;
check_time_1([{'*', _Now} | Rest], true) ->
    check_time_1(Rest, true);
check_time_1([{Now, Now} | Rest], true) ->
    check_time_1(Rest, true);
check_time_1([{List, Now} | Rest], true) when is_list(List) ->
    check_time_1(Rest, lists:member(Now, List));
check_time_1([_Other | _Rest], _CheckFlag) ->
    false.

process(Key, #task{mfa_to_exec = MFA,
                   next_exec_at = NextTime,
                   max_times = MaxTimes,
                   exec_times = ExecTimes} = Task,
               _Now, true) ->
    ?printlog("the task is running..~p~n", [Key]),
    Task1 = 
        case {MaxTimes, ExecTimes} of
            {undefined, _} ->
                execute_task_exact(MFA),
                Task#task{exec_times = ExecTimes + 1};
            {_, _} when MaxTimes =< ExecTimes ->
                Task#task{status = finish};
            {_, _} when is_integer(MaxTimes), MaxTimes == ExecTimes +1 ->
                execute_task_exact(MFA),
                Task#task{exec_times = ExecTimes + 1,
                          status = finish};
            {_, _} when is_integer(MaxTimes), MaxTimes > ExecTimes + 1 ->
                execute_task_exact(MFA),
                Task#task{exec_times = ExecTimes + 1};
            _Other ->
                Task
        end,
    Task2 =  
        case NextTime of
            {interval, {Secs, Interval}} ->
                Task1#task{next_exec_at = {interval, {Secs + Interval, Interval}}};
            _ ->
                Task1
        end,
    update_task(Key, Task2);
process(Key, #task{next_exec_at = {interval, {Secs, Interval}}} = Task,
            {_, _, _, _, _, NowSecs}, false) when Secs < NowSecs ->
    Delta = (NowSecs - Secs) div Interval,
    NewSecs = 
        case (Secs + Delta * Interval) of
            NowSecs -> NowSecs + Interval;
            _ -> Secs + (Delta + 2) * Interval
    end,
    ?printlog("update interval to ~p~n", [NewSecs]),
    update_task(Key, Task#task{next_exec_at = {interval, {NewSecs, Interval}}});
process(_Key, _Task, _Now, false) ->
    ignore.

execute_task_exact({Mod, Func, Arg}) ->
    spawn(fun() -> erlang:apply(Mod, Func, Arg) end).

update_task(Key, Task) ->
    ets:insert(?CRONTAB, {Key, Task}).

%% @doc parse task from tuple
parse_task({Mi, H, D, Mo, W, MFA}) ->
    parse_task({Mi, H, D, Mo, W, MFA, []});
parse_task({Mi, H, D, Mo, W, {M, F, A}, Options} = Task0)
                    when is_atom(M), is_atom(F), is_list(A) ->
    ?printlog("parsing task: ~p~n", [Task0]),
    Task = check_task_options(#task{mfa_to_exec = {M, F, A}}, Options),
    case proplists:get_value(interval, Options, normal) of
        normal ->
            DateTime = [check_task_datetime(X) || X <- [Mi, H, D, Mo, W]],
            Task#task{next_exec_at = {normal, list_to_tuple(DateTime)}};
        Int when is_integer(Int) ->
            case Task#task.start_after of
                undefined ->
                    ?printlog("start_after option is needed for interval task.~n", []),
                    throw(bad_task);
                StartAfter ->
                    Task#task{next_exec_at = {interval, {StartAfter, Int * 60}}}
            end;
        Other ->
            ?printlog("bad interval option found: ~p,"
                    "only integer is allowed~n", [Other]),
            throw(bad_task)
    end;
parse_task(Task) ->
    ?printlog("bad task found: ~p~n", [Task]),
    throw(bad_task).

check_task_options(Task, []) ->
    Task;
check_task_options(Task, [{start, {Date, Time}} | Rest]) ->
    StartAfter = get_task_seconds(Date, Time),
    check_task_options(Task#task{start_after = StartAfter}, Rest);
check_task_options(_Task, [{start, BadStart} | _Rest]) ->
    ?printlog("bad start option of task found: ~p~n", [BadStart]),
    throw(bad_task);
check_task_options(Task, [{finish, {Date, Time}} | Rest]) ->
    FinishBefore = get_task_seconds(Date, Time),
    check_task_options(Task#task{finish_before = FinishBefore}, Rest);
check_task_options(_Task, [{finish, BadFinish} | _Rest]) ->
    ?printlog("bad finish option of task found: ~p~n", [BadFinish]),
    throw(bad_task);
check_task_options(Task, [{name, Name} | Rest]) ->
    check_task_options(Task#task{name = Name}, Rest);
check_task_options(Task, [{max, MaxTimes} | Rest]) when is_integer(MaxTimes) ->
    check_task_options(Task#task{max_times = MaxTimes}, Rest);
check_task_options(_, [{max, Other} | _]) ->
    ?printlog("bad max option of task found: ~p,"
            "only integer is allowed.~n", [Other]),
    throw(bad_task);
check_task_options(Task, [{persistent, Bool} | Rest]) when is_boolean(Bool) ->
    check_task_options(Task#task{persistent = Bool}, Rest);
check_task_options(_, [{persistent, Other} | _]) ->
    ?printlog("bad persistent option of task found: ~p"
            ", only true and false is allowed.~n", [Other]),
    throw(bad_task);
check_task_options(Task, [_ | Rest]) ->
    check_task_options(Task, Rest).

check_task_datetime('*') ->
    '*';
check_task_datetime(List) when is_list(List) ->
    List;
check_task_datetime(Int) when is_integer(Int) ->
    Int;
check_task_datetime(Atom) when is_atom(Atom) ->
    Str = atom_to_list(Atom),
    RE = "^(\\d+)-(\\d+)(/(\\d+))?$",
    case re:run(Str, RE, [{capture, [1,2,4], list}]) of
        {match, [From, To, []]} ->
            lists:seq(list_to_integer(From), list_to_integer(To));
        {match, [From, To, Step]} ->
            lists:seq(list_to_integer(From), list_to_integer(To), list_to_integer(Step));
        nomatch ->
            ?printlog("failed to parse task attribute: ~p~n", [Atom]),
            throw(bad_task)
    end;
check_task_datetime(Other) ->
    ?printlog("failed to parse datetime of task: ~p~n", [Other]),
    throw(bad_task).

%% @doc generate the task key
keygen() ->
    <<Mac:128/integer>> = crypto:md5(crypto:rand_bytes(64)),
    lists:flatten(io_lib:format("~.16B", [Mac])).

get_task_seconds(Date, Time) ->
    {Date0, Time0} = calendar:local_time(),
    Date2 =
        if
            Date == '$nowdate' -> Date0;
            true -> Date
        end,
    Time2 =
        if
            Time == '$nowtime' -> Time0;
            true -> Time
        end,
    case catch calendar:datetime_to_gregorian_seconds({Date2, Time2}) of
        Seconds when is_integer(Seconds) ->
            Seconds;
        _Other ->
            ?printlog("failed to parse task option: ~p~n", [{Date, Time}]),
            throw(bad_task)
    end.

safe_call(Request) ->
    check_server_running(),
    gen_server:call(?SERVER, Request).

check_server_running() ->
    case whereis(?MODULE) of
        undefined -> throw({error, "cron_service is not running now"});
        _ -> ignore
    end.


%%------------------------------------------------------------------------------
%% test functions
%%------------------------------------------------------------------------------
%% @private
load_list_test() ->
    List = [{30, '*', '1-28/9', '*', '*', {?MODULE, dosth, ["half an hour"]}},
            {0, 0, 0, 0, 0, {?MODULE, dosth, ["interval task"]},
                    [{name, interval}, {start, {'$nowdate', '$nowtime'}},{interval, 1}]}],
    ok == load_task_from_list(List).

%% @hidden
load_record_test() ->
    Now = calendar:local_time(),
    {{_Y, Mo, D}, {H, _Mi, _S}} = Now,
    Secs = calendar:datetime_to_gregorian_seconds(Now),
    Task1 = #task{name = test,
                  next_exec_at = {interval, {Secs+10, 120}},
                  mfa_to_exec = {?MODULE, dosth, ["payload1111"]},
                  finish_before = Secs -1,
                  max_times = 4},
    Task2 = #task{name = test,
                  next_exec_at = {normal, {lists:seq(0,59), H, D, Mo, '*'}},
                  mfa_to_exec = {?MODULE, dosth, ["payload2222"]},
                  start_after  = Secs + 180,
                  finish_before = undefined,
                  max_times = undefined},

    load_task([Task1, Task2]).

%% @hidden
dosth(Payload) ->
    ?printlog("do something: ~p~n", [Payload]).


%% @doc 返回当地日期和时间.
%% 请参考 <a href='http://www.erlang.org/doc/man/calendar.html'>calender module</a> 获取更多类型信息.
%% @spec datetime() -> {date(), time()}
datetime() ->
    {date(), time()}.