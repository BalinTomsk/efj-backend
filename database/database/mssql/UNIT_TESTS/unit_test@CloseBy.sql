SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_GetCloseLake (Close By).
  Uses real table dbo.lake / dbo.Tributaries. Transaction is rolled back at end -
  database state restored.

  TEST 1 - Single point, single lake -> no closeby lake found
  TEST 2 - Single point, two lakes far apart -> no closeby lake found
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: Single Point for lake no closeby
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake1 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_name, locType, Lake_id) VALUES ('Lake', 1, @Lake1);
    UPDATE Tributaries SET lat = 1, lon = 1 WHERE Main_Lake_id = @Lake1 AND side = 16;
    DECLARE @Result1 int = (SELECT COUNT(*) FROM dbo.fn_GetCloseLake(@Lake1, 1, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result1 = 0
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: single lake with no closeby found none';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0 closeby lakes, got ' + CAST(@Result1 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: Single Point for single lake no closeby (second lake far away)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake2a uniqueidentifier = NEWID();
    DECLARE @Lake2b uniqueidentifier = NEWID();
    INSERT INTO lake (lake_name, locType, Lake_id) VALUES ('Lake',  1, @Lake2a);
    INSERT INTO lake (lake_name, locType, Lake_id) VALUES ('Lake2', 1, @Lake2b);
    UPDATE Tributaries SET lat = 1, lon = 1 WHERE Main_Lake_id = @Lake2a AND side = 16;
    UPDATE Tributaries SET lat = 2, lon = 2 WHERE Main_Lake_id = @Lake2b AND side = 16;
    DECLARE @Result2 int = (SELECT COUNT(*) FROM dbo.fn_GetCloseLake(@Lake2a, 1, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result2 = 0
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two distant lakes -> no closeby found';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0 closeby lakes, got ' + CAST(@Result2 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
