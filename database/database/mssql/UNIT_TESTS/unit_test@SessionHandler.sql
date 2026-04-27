SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for SessionHandler'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'

----------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit Tests for dbo.fn_SessionHandlerTodayConsumedPages
-- Created by GitHub Copilot in SSMS - review carefully before executing
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 1: No matching records returns 0
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT1
DECLARE @test_name SYSNAME = 'TestSHT1 [fn_SessionHandlerTodayConsumedPages] returns 0 when no records exist';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    -- Clean test data
    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_01';

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('192.168.1.1', 'UT_HOST_01');

    IF @result <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 0, actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT1
GO

-- TEST 2: Single IPv4 record sums correctly
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT2
DECLARE @test_name SYSNAME = 'TestSHT2 [fn_SessionHandlerTodayConsumedPages] sums single IPv4 record';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_02';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, counterPage, baned, userAgent)
    VALUES (GETUTCDATE(), 'UT_HOST_02', '10.0.0.1', 15, 0, 'UT_HOST_02');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.1', 'UT_HOST_02');

    IF @result <> 15
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 15, actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT2
GO

-- TEST 7: Different host is excluded
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT7
DECLARE @test_name SYSNAME = 'TestSHT7 [fn_SessionHandlerTodayConsumedPages] excludes different host';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_07A', 'UT_HOST_07B');

    INSERT INTO dbo.SessionHandler (startSess, host, ip4,   counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_07A', '10.0.0.7',   10, 0, 'UT_HOST_07'),
        (GETUTCDATE(), 'UT_HOST_07B', '10.0.0.8',  30, 0, 'UT_HOST_08');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.7',   'UT_HOST_07A');

    IF @result <> 10
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 10 (other host excluded), actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT7
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.spPersistIpBan
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 1: Inserts new record when ip4 does not exist
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestPIB1

DECLARE @test_name SYSNAME = 'TestPIB1 [spPersistIpBan] inserts new record when ip4 does not exist';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_PIB_01';

    DECLARE @id uniqueidentifier = NEWID();

    EXEC dbo.spPersistIpBan
        @counterPage = 5,
        @agent       = N'UT_AGENT_01',
        @host        = N'UT_HOST_PIB_01',
        @ip4         = '192.168.10.1',
        @startPage   = N'/unit-test-start',
        @baned       = 1,
        @id          = @id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND ip4 = '192.168.10.1'
          AND userAgent = N'UT_AGENT_01'
          AND host = 'UT_HOST_PIB_01'
          AND startPage = '/unit-test-start'
          AND baned = 1
          AND counterPage = 5
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected inserted row was not found';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB1
GO


-- TEST 2: Updates existing record when matching non-empty ip4 exists
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestPIB2

DECLARE @test_name SYSNAME = 'TestPIB2 [spPersistIpBan] updates existing record when matching ip4 exists';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_02_OLD', 'UT_HOST_PIB_02_NEW');

    DECLARE @id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@id, GETDATE(), N'OLD_AGENT', 'UT_HOST_PIB_02_OLD', '/old', 0, '192.168.10.2', 1);

    EXEC dbo.spPersistIpBan
        @counterPage = 9,
        @agent       = N'NEW_AGENT',
        @host        = N'UT_HOST_PIB_02_NEW',
        @ip4         = '192.168.10.2',
        @startPage   = N'/new-start-page',
        @baned       = 0,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND ip4 = '192.168.10.2'
          AND userAgent = N'NEW_AGENT'
          AND host = 'UT_HOST_PIB_02_NEW'
          AND baned = 1
          AND counterPage = 9
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected existing row to be updated';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' procedure inserted a new row instead of updating existing row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB2
GO


-- TEST 3: Empty ip4 does not update existing empty-ip row; inserts new row instead
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestPIB3

DECLARE @test_name SYSNAME = 'TestPIB3 [spPersistIpBan] inserts when ip4 parameter is empty string';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_03_OLD', 'UT_HOST_PIB_03_NEW');

    DECLARE @old_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@old_id, GETDATE(), N'OLD_AGENT', 'UT_HOST_PIB_03_OLD', '/old', 0, '', 1);

    EXEC dbo.spPersistIpBan
        @counterPage = 4,
        @agent       = N'NEW_AGENT_EMPTY_IP',
        @host        = N'UT_HOST_PIB_03_NEW',
        @ip4         = '',
        @startPage   = N'/empty-ip-start',
        @baned       = 1,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
          AND ip4 = ''
          AND userAgent = N'NEW_AGENT_EMPTY_IP'
          AND host = 'UT_HOST_PIB_03_NEW'
          AND startPage = '/empty-ip-start'
          AND baned = 1
          AND counterPage = 4
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected new row for empty ip4 was not inserted';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @old_id
          AND userAgent = N'OLD_AGENT'
          AND host = 'UT_HOST_PIB_03_OLD'
          AND counterPage = 1
          AND baned = 0
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' existing empty-ip row should not have been updated';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB3
GO


-- TEST 4: Insert respects @baned parameter when no existing ip4 match exists
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestPIB4

DECLARE @test_name SYSNAME = 'TestPIB4 [spPersistIpBan] insert stores @baned value when no match exists';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_PIB_04';

    DECLARE @id uniqueidentifier = NEWID();

    EXEC dbo.spPersistIpBan
        @counterPage = 2,
        @agent       = N'UT_AGENT_04',
        @host        = N'UT_HOST_PIB_04',
        @ip4         = '192.168.10.4',
        @startPage   = N'/not-banned',
        @baned       = 0,
        @id          = @id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND ip4 = '192.168.10.4'
          AND baned = 0
          AND counterPage = 2
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected inserted row with baned = 0';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB4
GO


-- TEST 5: Update always sets baned = 1 even when @baned = 0
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestPIB5

DECLARE @test_name SYSNAME = 'TestPIB5 [spPersistIpBan] update always sets baned to 1';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_05_OLD', 'UT_HOST_PIB_05_NEW');

    DECLARE @id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@id, GETDATE(), N'OLD_AGENT_05', 'UT_HOST_PIB_05_OLD', '/old', 0, '192.168.10.5', 1);

    EXEC dbo.spPersistIpBan
        @counterPage = 8,
        @agent       = N'NEW_AGENT_05',
        @host        = N'UT_HOST_PIB_05_NEW',
        @ip4         = '192.168.10.5',
        @startPage   = N'/ignored-on-update',
        @baned       = 0,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND baned = 1
          AND counterPage = 8
          AND userAgent = N'NEW_AGENT_05'
          AND host = 'UT_HOST_PIB_05_NEW'
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected update to set baned = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB5
GO


-- TEST 6: Multiple rows with same ip4 are all updated
-----------------------------------------------------------------------------------------------------------------------------------------------
-- TEST: Update existing row by ip4
BEGIN TRAN TestPIB_Update

DECLARE @test_name SYSNAME = 'TestPIB_Update [spPersistIpBan] updates existing row by ip4';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.10.6';

    DECLARE @existing_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@existing_id, 'OLD_AGENT', 'UT_HOST_OLD', '/old', 0, '192.168.10.6', 1);

    EXEC dbo.spPersistIpBan
        @counterPage = 12,
        @agent       = N'NEW_AGENT_06',
        @host        = N'UT_HOST_NEW',
        @ip4         = '192.168.10.6',
        @startPage   = N'/ignored',
        @baned       = 0,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @existing_id
          AND ip4 = '192.168.10.6'
          AND userAgent = 'NEW_AGENT_06'
          AND host = 'UT_HOST_NEW'
          AND baned = 1
          AND counterPage = 12
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected existing row to be updated';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' inserted new row instead of updating existing row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestPIB_Update
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.spRegisterPageHit
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 1: Inserts new record when today's ip4 does not exist
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH1

DECLARE @test_name SYSNAME = 'TestRPH1 [spRegisterPageHit] inserts new record when ip4 does not exist today';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.1';

    DECLARE @id uniqueidentifier = NEWID();

    EXEC dbo.spRegisterPageHit
        @counterPage = 3,
        @agent       = N'UT_AGENT_RPH_01',
        @host        = N'UT_HOST_RPH_01',
        @ip4         = '192.168.20.1',
        @startPage   = N'/rph-start-01',
        @baned       = 1,
        @id          = @id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND ip4 = '192.168.20.1'
          AND userAgent = 'UT_AGENT_RPH_01'
          AND host = 'UT_HOST_RPH_01'
          AND startPage = '/rph-start-01'
          AND baned = 1
          AND counterPage = 3
          AND activityDate = CAST(GETUTCDATE() AS date)
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected inserted row was not found';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH1
GO


-- TEST 2: Updates today's existing record by ip4 and increments counterPage
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH2

DECLARE @test_name SYSNAME = 'TestRPH2 [spRegisterPageHit] updates today row and increments counterPage';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.2';

    DECLARE @existing_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@existing_id, GETUTCDATE(), 'OLD_AGENT_RPH_02', 'UT_HOST_RPH_02_OLD', '/old-page', 1, '192.168.20.2', 7);

    EXEC dbo.spRegisterPageHit
        @counterPage = 5,
        @agent       = N'NEW_AGENT_RPH_02',
        @host        = N'UT_HOST_RPH_02_NEW',
        @ip4         = '192.168.20.2',
        @startPage   = N'/new-page',
        @baned       = 1,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @existing_id
          AND ip4 = '192.168.20.2'
          AND userAgent = 'NEW_AGENT_RPH_02'
          AND host = 'UT_HOST_RPH_02_NEW'
          AND startPage = '/new-page'
          AND baned = 0
          AND counterPage = 12
          AND activityDate = CAST(GETUTCDATE() AS date)
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected today row to be updated and counterPage incremented to 12';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' inserted new row instead of updating today row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH2
GO


-- TEST 3: Same ip4 from yesterday does not update; inserts new row for today
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH3

DECLARE @test_name SYSNAME = 'TestRPH3 [spRegisterPageHit] inserts today row when only yesterday row exists';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.3';

    DECLARE @old_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@old_id, DATEADD(day, -1, GETUTCDATE()), 'OLD_AGENT_RPH_03', 'UT_HOST_RPH_03_OLD', '/old-page', 1, '192.168.20.3', 10);

    EXEC dbo.spRegisterPageHit
        @counterPage = 4,
        @agent       = N'NEW_AGENT_RPH_03',
        @host        = N'UT_HOST_RPH_03_NEW',
        @ip4         = '192.168.20.3',
        @startPage   = N'/today-page',
        @baned       = 0,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
          AND ip4 = '192.168.20.3'
          AND userAgent = 'NEW_AGENT_RPH_03'
          AND host = 'UT_HOST_RPH_03_NEW'
          AND startPage = '/today-page'
          AND baned = 0
          AND counterPage = 4
          AND activityDate = CAST(GETUTCDATE() AS date)
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected new today row was not inserted';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @old_id
          AND activityDate = CAST(DATEADD(day, -1, GETUTCDATE()) AS date)
          AND counterPage = 10
          AND baned = 1
          AND userAgent = 'OLD_AGENT_RPH_03'
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' yesterday row should not have been updated';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH3
GO


-- TEST 4: Empty ip4 does not update existing empty-ip row; inserts new row
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH4

DECLARE @test_name SYSNAME = 'TestRPH4 [spRegisterPageHit] inserts when ip4 parameter is empty string';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_RPH_04_OLD', 'UT_HOST_RPH_04_NEW');

    DECLARE @old_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@old_id, GETUTCDATE(), 'OLD_AGENT_RPH_04', 'UT_HOST_RPH_04_OLD', '/old-empty-ip', 1, '', 6);

    EXEC dbo.spRegisterPageHit
        @counterPage = 2,
        @agent       = N'NEW_AGENT_RPH_04',
        @host        = N'UT_HOST_RPH_04_NEW',
        @ip4         = '',
        @startPage   = N'/new-empty-ip',
        @baned       = 0,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @new_id
          AND ip4 = ''
          AND userAgent = 'NEW_AGENT_RPH_04'
          AND host = 'UT_HOST_RPH_04_NEW'
          AND startPage = '/new-empty-ip'
          AND baned = 0
          AND counterPage = 2
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected new empty-ip row was not inserted';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @old_id
          AND userAgent = 'OLD_AGENT_RPH_04'
          AND host = 'UT_HOST_RPH_04_OLD'
          AND startPage = '/old-empty-ip'
          AND baned = 1
          AND counterPage = 6
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' existing empty-ip row should not have been updated';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH4
GO


-- TEST 5: Insert respects @baned parameter when no today match exists
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH5

DECLARE @test_name SYSNAME = 'TestRPH5 [spRegisterPageHit] insert stores @baned value when no match exists';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.5';

    DECLARE @id uniqueidentifier = NEWID();

    EXEC dbo.spRegisterPageHit
        @counterPage = 1,
        @agent       = N'UT_AGENT_RPH_05',
        @host        = N'UT_HOST_RPH_05',
        @ip4         = '192.168.20.5',
        @startPage   = N'/insert-baned-true',
        @baned       = 1,
        @id          = @id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @id
          AND ip4 = '192.168.20.5'
          AND baned = 1
          AND counterPage = 1
          AND startPage = '/insert-baned-true'
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected inserted row with baned = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH5
GO


-- TEST 6: Update always sets baned = 0 even when @baned = 1
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRPH6

DECLARE @test_name SYSNAME = 'TestRPH6 [spRegisterPageHit] update always sets baned to 0';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.6';

    DECLARE @existing_id uniqueidentifier = NEWID();
    DECLARE @new_id uniqueidentifier = NEWID();

    INSERT INTO dbo.SessionHandler
        (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES
        (@existing_id, GETUTCDATE(), 'OLD_AGENT_RPH_06', 'UT_HOST_RPH_06_OLD', '/old', 1, '192.168.20.6', 3);

    EXEC dbo.spRegisterPageHit
        @counterPage = 2,
        @agent       = N'NEW_AGENT_RPH_06',
        @host        = N'UT_HOST_RPH_06_NEW',
        @ip4         = '192.168.20.6',
        @startPage   = N'/new',
        @baned       = 1,
        @id          = @new_id;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SessionHandler
        WHERE id = @existing_id
          AND baned = 0
          AND counterPage = 5
          AND userAgent = 'NEW_AGENT_RPH_06'
          AND host = 'UT_HOST_RPH_06_NEW'
          AND startPage = '/new'
    )
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected update to set baned = 0 and increment counterPage to 5';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestRPH6
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------

