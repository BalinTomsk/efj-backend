-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_enx_merge' AND type = 'P')
    DROP PROCEDURE dbo.sp_enx_merge
GO

/*
 *  refresh actual data

    Usage: 
        EXEC dbo.sp_enx_merge
        select * from global_configuration

*/

CREATE PROCEDURE dbo.sp_enx_merge @dt DATE = '20010101'
WITH EXEC AS CALLER
AS
BEGIN TRY
    SET NOCOUNT ON;

     declare @node int = (select CAST(config_value AS int) from global_configuration WHERE config_attribute = 'node');

     UPDATE global_configuration SET config_value = CAST(getdate()  as sysname) WHERE config_attribute =  'job_executed';

     /* delete data of second level  */

    SELECT @@ROWCOUNT AS result
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_enx_job' AND type = 'P')
    DROP PROCEDURE dbo.sp_enx_job
GO

CREATE PROCEDURE dbo.sp_enx_job @starttime nvarchar(8), @dbname sysname
WITH EXEC AS CALLER
AS
BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @job sysname = N'ENVX';
    DECLARE @servername nvarchar(28) = @@SERVERNAME
    DECLARE @startdate nvarchar(8) = CONVERT(VARCHAR(10), getdate(), 112)
    DECLARE @ReturnCode INT = 0
    DECLARE @jobId BINARY(16)

    IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = @job)
    BEGIN
        EXEC msdb.dbo.sp_delete_job @job_name = @job;
    END

    EXEC @ReturnCode = msdb.dbo.sp_add_job  @job_name = @job, 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0,     
        @job_id = @jobId OUTPUT

    DECLARE @cmdtemplate sysname = N'EXEC ' + @dbname + N'.dbo.sp_enx_merge'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_enx_merge', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=2, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=@cmdtemplate, 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'ENVX', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20200212, 
		@active_end_date=99991231, 
		@active_start_time=100000, 
		@active_end_time=235959, 
		@schedule_uid=N'363e20f0-a03e-4849-8692-319b0fb84fad'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

    EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
  
    RETURN @@ROWCOUNT
QuitWithRollback:
    IF NOT EXISTS (SELECT * FROM  msdb.dbo.sysschedules WHERE name = @job)
        RAISERROR ('FAILED: %s Failed to create job %s on %s in %d  ', 16, -1, @job, @servername, @dbname ) 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------

IF NOT EXISTS (select * from [msdb].[dbo].[sysjobs] WHERE name='sp_enx_job')
BEGIN
    declare @start_time varchar(16) = (select CAST(config_value AS int) from global_configuration WHERE config_attribute = 'job_start')
    declare @dbname sysname = DB_NAME()
    EXEC dbo.sp_enx_job  @start_time, @dbname
END
GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
