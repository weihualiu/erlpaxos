
%% definition of cron task scheduled by cron_service.

-record(task, {
      name,             %% Task name
      next_exec_at,     %% Next datetime to execute
      mfa_to_exec,      %% {Module, Function, Arg}
      start_after,      %% Start to match 'next_exec_at' after 'start_after'
      finish_before,    %% Finish to match 'next_exec_at' before 'finish_before'
      max_times,        %% Max times of executing 'mfa_to_exec' during match period
      persistent,       %% The task will be persistent if this flag is setted
      
      created_at,       %% Timestamp of creating this task
      exec_times,       %% Times of executing 'mfa_to_exec'
      status            %% One of these three status:ready, cancel, finish
}).

-define(printlog(Format, Data), error_logger:info_msg("~p:~p " ++ Format, [?MODULE,?LINE]++Data)).
-define(printerr(Format, Data), error_logger:error_msg(?MODULE, ?LINE, Format, Data)).
-define(printmsg(Format, Data), error_logger:warning_msg("~p:~p " ++ Format, [?MODULE,?LINE]++Data)).