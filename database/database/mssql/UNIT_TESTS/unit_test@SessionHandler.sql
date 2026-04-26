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

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('192.168.1.1', '', 'UT_HOST_01');

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

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES (GETUTCDATE(), 'UT_HOST_02', '10.0.0.1', '', 15, 0, 'UT_HOST_02');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.1', '', 'UT_HOST_02');

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

-- TEST 3: Multiple IPv4 records sum correctly
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT3
DECLARE @test_name SYSNAME = 'TestSHT3 [fn_SessionHandlerTodayConsumedPages] sums multiple IPv4 records';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_03';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_03', '10.0.0.1', '', 10, 0, 'UT_HOST_01'),
        (GETUTCDATE(), 'UT_HOST_03', '10.0.0.2', '', 20, 0, 'UT_HOST_02'),
        (GETUTCDATE(), 'UT_HOST_03', '10.0.0.3', '', 15, 0, 'UT_HOST_03');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.2', '', 'UT_HOST_03');

    IF @result <> 45
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 45, actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT3
GO

-- TEST 4: IPv6 record sums correctly
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT4
DECLARE @test_name SYSNAME = 'TestSHT4 [fn_SessionHandlerTodayConsumedPages] sums IPv6 record';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_04';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES (GETUTCDATE(), 'UT_HOST_04', '', '2001:db8::1', 25, 0, 'UT_HOST_03');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('', '2001:db8::1', 'UT_HOST_04');

    IF @result <> 25
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 25, actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT4
GO

-- TEST 5: Banned records are excluded
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT5
DECLARE @test_name SYSNAME = 'TestSHT5 [fn_SessionHandlerTodayConsumedPages] excludes banned records';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_05';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_05', '10.0.0.1', '', 10, 0, 'UT_HOST_01'),
        (GETUTCDATE(), 'UT_HOST_05', '10.0.0.5', '', 50, 1, 'UT_HOST_05');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.5', '', 'UT_HOST_05');

    IF @result <> 10
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 10 (banned record excluded), actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT5
GO

-- TEST 6: Yesterday's records are excluded
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT6
DECLARE @test_name SYSNAME = 'TestSHT6 [fn_SessionHandlerTodayConsumedPages] excludes yesterday records';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_06';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_06', '10.0.0.6', '', 10, 0, 'UT_HOST_06'),
        (DATEADD(DAY, -1, GETUTCDATE()), 'UT_HOST_06', '10.0.0.6', '', 40, 0, 'UT_HOST_06');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.6', '', 'UT_HOST_06');

    IF @result <> 10
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 10 (yesterday excluded), actual ' + CAST(@result AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT6
GO

-- TEST 7: Different host is excluded
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT7
DECLARE @test_name SYSNAME = 'TestSHT7 [fn_SessionHandlerTodayConsumedPages] excludes different host';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_07A', 'UT_HOST_07B');

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_07A', '10.0.0.7', '', 10, 0, 'UT_HOST_07'),
        (GETUTCDATE(), 'UT_HOST_07B', '10.0.0.8', '', 30, 0, 'UT_HOST_08');

    DECLARE @result INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.7', '', 'UT_HOST_07A');

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

-- TEST 9: Mixed IPv4 and IPv6 records for same host
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestSHT9
DECLARE @test_name SYSNAME = 'TestSHT9 [fn_SessionHandlerTodayConsumedPages] sums both IPv4 and IPv6';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_09';

    INSERT INTO dbo.SessionHandler (startSess, host, ip4, ip6, counterPage, baned, userAgent)
    VALUES 
        (GETUTCDATE(), 'UT_HOST_09', '10.0.0.9', '', 15, 0, 'UT_HOST_09'),
        (GETUTCDATE(), 'UT_HOST_09', '', '2001:db8::9', 20, 0, 'UT_HOST_08A');

    -- Query with IPv4
    DECLARE @result_ipv4 INT = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.9', '', 'UT_HOST_09');
    
    -- Query with IPv6
    DECLARE @result_ipv6 INT = dbo.fn_SessionHandlerTodayConsumedPages('', '2001:db8::9', 'UT_HOST_09');

    IF @result_ipv4 <> 15
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' IPv4 expected 15, actual ' + CAST(@result_ipv4 AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF @result_ipv6 <> 20
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' IPv6 expected 20, actual ' + CAST(@result_ipv6 AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestSHT9
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
