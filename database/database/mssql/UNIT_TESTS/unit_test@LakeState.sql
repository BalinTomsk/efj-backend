SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for Lake_State unit/range CHECK constraints'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'
-- Verifies the CK_Lake_State_* range constraints: valid values and NULLs are
-- accepted; out-of-range values are rejected. Each test runs in its own
-- transaction and rolls back, so the DB is unchanged when finished.
-- A rejected INSERT must be caught (never SELECTed) so its error does not leak
-- into cleaned.txt and look like a failure.
-- prep lake_id used by every test (FK target). Rolled back with each test.
----------------------------------------------------------------------------------------------------------

PRINT '-----------------------------------------------------------------------------------------------------------------------------'
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS1
DECLARE @test_name SYSNAME = 'TestLS1 [Lake_State] valid in-range row is accepted';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');

    -- 2. execute unit test: every column within its allowed range
    INSERT INTO Lake_State ([month], lake_id, PH, Phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium
        , Chloride, Bicarbonate, Transparency, Oxygen, Salinity, Clarity, Velocity, water_degree, air_degree)
        VALUES (6, 'f1f1f1f1-0000-0000-0000-000000000001', 7.2, 0.05, 596, 955, 449, 372, 90
        , 11, 482, 1.5, 9.1, 6, 1.2, 0.8, 18, -5);

    DECLARE @result1 int = (SELECT COUNT(*) FROM Lake_State WHERE lake_id = 'f1f1f1f1-0000-0000-0000-000000000001' AND [month] = 6);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

    IF @result1 <> 1
       RAISERROR ('FAILED: %s valid row must be accepted %d', 16, -1, @test_name, @result1)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS1
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS2
DECLARE @test_name SYSNAME = 'TestLS2 [Lake_State] water_degree > 100 is rejected';
DECLARE @threw bit = 0;

SET NOCOUNT ON;
INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');
BEGIN TRY
    INSERT INTO Lake_State ([month], lake_id, water_degree) VALUES (1, 'f1f1f1f1-0000-0000-0000-000000000001', 150);
END TRY
BEGIN CATCH
    SET @threw = 1;   -- swallow the expected CHECK violation (do not SELECT it)
END CATCH

    IF @threw <> 1
       RAISERROR ('FAILED: %s water_degree=150 must be rejected', 16, -1, @test_name)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS2
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS3
DECLARE @test_name SYSNAME = 'TestLS3 [Lake_State] PH outside 0..14 is rejected';
DECLARE @threw bit = 0;

SET NOCOUNT ON;
INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');
BEGIN TRY
    INSERT INTO Lake_State ([month], lake_id, PH) VALUES (1, 'f1f1f1f1-0000-0000-0000-000000000001', 20);
END TRY
BEGIN CATCH
    SET @threw = 1;
END CATCH

    IF @threw <> 1
       RAISERROR ('FAILED: %s PH=20 must be rejected', 16, -1, @test_name)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS3
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS4
DECLARE @test_name SYSNAME = 'TestLS4 [Lake_State] NULL measurements are allowed';

BEGIN TRY  SET NOCOUNT ON;
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');

    -- only the required key columns; all measurements left NULL
    INSERT INTO Lake_State ([month], lake_id) VALUES (3, 'f1f1f1f1-0000-0000-0000-000000000001');

    DECLARE @result1 int = (SELECT COUNT(*) FROM Lake_State WHERE lake_id = 'f1f1f1f1-0000-0000-0000-000000000001' AND [month] = 3);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

    IF @result1 <> 1
       RAISERROR ('FAILED: %s NULL measurements must be accepted %d', 16, -1, @test_name, @result1)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS4
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS5
DECLARE @test_name SYSNAME = 'TestLS5 [Lake_State] negative concentration (Oxygen) is rejected';
DECLARE @threw bit = 0;

SET NOCOUNT ON;
INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');
BEGIN TRY
    INSERT INTO Lake_State ([month], lake_id, Oxygen) VALUES (1, 'f1f1f1f1-0000-0000-0000-000000000001', -5);
END TRY
BEGIN CATCH
    SET @threw = 1;
END CATCH

    IF @threw <> 1
       RAISERROR ('FAILED: %s Oxygen=-5 must be rejected', 16, -1, @test_name)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS5
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestLS6
DECLARE @test_name SYSNAME = 'TestLS6 [Lake_State] sub-zero air_degree is allowed, extreme is rejected';
DECLARE @threw bit = 0;

BEGIN TRY  SET NOCOUNT ON;
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES ('f1f1f1f1-0000-0000-0000-000000000001', 2, N'River', 'ABCDE');

    -- valid sub-zero air temperature accepted
    INSERT INTO Lake_State ([month], lake_id, air_degree) VALUES (1, 'f1f1f1f1-0000-0000-0000-000000000001', -40);
    DECLARE @result1 int = (SELECT COUNT(*) FROM Lake_State WHERE lake_id = 'f1f1f1f1-0000-0000-0000-000000000001' AND [month] = 1);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

-- impossibly cold air temperature rejected
BEGIN TRY
    INSERT INTO Lake_State ([month], lake_id, air_degree) VALUES (2, 'f1f1f1f1-0000-0000-0000-000000000001', -300);
END TRY
BEGIN CATCH
    SET @threw = 1;
END CATCH

    IF @result1 <> 1 OR @threw <> 1
       RAISERROR ('FAILED: %s air -40 accept=%d, air -300 reject expected', 16, -1, @test_name, @result1)
    ELSE
        PRINT 'PASSED ' + @test_name
IF XACT_STATE() <> 0 ROLLBACK TRAN TestLS6
GO
