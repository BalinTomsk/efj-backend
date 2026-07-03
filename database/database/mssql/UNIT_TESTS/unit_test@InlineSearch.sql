SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.FishSearchVariant.
  Database may not be empty - relies on pre-existing fish rows matching the searched names.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST 1 - Black Bullhead -> single exact match
  TEST 2 - Sucker, Longnose -> six variants, one exact match
  TEST 3 - Salmon -> single exact match
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: Black Bullhead
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl1 TABLE (line sysname, irank int);
    INSERT INTO @Tbl1 SELECT * FROM dbo.FishSearchVariant(N'Black Bullhead');
    DECLARE @T1Total int = (SELECT COUNT(*) FROM @Tbl1);
    DECLARE @T1Exact int = (SELECT COUNT(*) FROM @Tbl1 WHERE line LIKE N'Black Bullhead');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T1Total = 1 AND @T1Exact = 1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Black Bullhead returned single exact match';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@T1Total AS varchar) + ', exact=' + CAST(@T1Exact AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: Sucker, Longnose
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl2 TABLE (line sysname, irank int);
    INSERT INTO @Tbl2 SELECT * FROM dbo.FishSearchVariant(N'Sucker, Longnose');
    DECLARE @T2Total int = (SELECT COUNT(*) FROM @Tbl2);
    DECLARE @T2Exact int = (SELECT COUNT(*) FROM @Tbl2 WHERE line LIKE N'Sucker, Longnose');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T2Total = 6 AND @T2Exact = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Sucker, Longnose returned six variants with one exact match';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@T2Total AS varchar) + ', exact=' + CAST(@T2Exact AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: Salmon
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl3 TABLE (line sysname, irank int);
    INSERT INTO @Tbl3 SELECT * FROM dbo.FishSearchVariant(N'Salmon');
    DECLARE @T3Total int = (SELECT COUNT(*) FROM @Tbl3);
    DECLARE @T3Exact int = (SELECT COUNT(*) FROM @Tbl3 WHERE line LIKE N'Salmon');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T3Total = 1 AND @T3Exact = 1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Salmon returned single exact match';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@T3Total AS varchar) + ', exact=' + CAST(@T3Exact AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
