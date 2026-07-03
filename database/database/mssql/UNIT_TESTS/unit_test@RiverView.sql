SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_ViewTributary / dbo.sp_assign_border.
  Uses real tables dbo.lake / dbo.Tributaries. Transaction is rolled back at end -
  database state restored.

  NOTE: TEST 4 duplicates TEST 3's setup and assertions - this duplication exists in the
  original test file (TestRV3/TestRV4 were byte-identical) and is preserved here unchanged;
  only the reporting structure and lake ids (now unique per test, to avoid a PK collision
  once merged into one shared transaction) were changed.

  TEST 1 - no tributaries for a bare river -> 0 rows either direction
  TEST 2 - no tributaries for a bare lake -> 0 rows either direction
  TEST 3 - lake reassigned as mouth for a river, after sp_assign_border -> 1 row each
  TEST 4 - (duplicate of TEST 3)
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: no tributaries for river
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake1 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake1, 2, N'River', 'UTRV1');
    DECLARE @R1a int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Lake1, 1, 256));
    DECLARE @R1b int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Lake1, 0, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1a = 0 AND @R1b = 0
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: bare river has no tributaries';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: dir1=' + CAST(@R1a AS varchar) + ' dir0=' + CAST(@R1b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: no tributaries for lake
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake2 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake2, 1, N'Lake', 'UTRV2');
    DECLARE @R2a int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Lake2, 1, 256));
    DECLARE @R2b int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Lake2, 0, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2a = 0 AND @R2b = 0
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: bare lake has no tributaries';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: dir1=' + CAST(@R2a AS varchar) + ' dir0=' + CAST(@R2b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: lake reassigned as mouth for a river
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @River3 uniqueidentifier = NEWID();
    DECLARE @Mouth3 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@River3, 2, N'River', 'UTRV3');
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Mouth3, 1, N'Lake', 'UTRV4');
    UPDATE Tributaries SET [lake_id] = @Mouth3
        WHERE lake_id = @River3 AND main_lake_id = @River3 AND side = 32;
    EXEC sp_assign_border @lake_id = @River3;
    DECLARE @R3a int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@River3, 1, 256));
    DECLARE @R3b int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Mouth3, 1, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3a = 1 AND @R3b = 1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake reassigned as mouth for river';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: river=' + CAST(@R3a AS varchar) + ' mouth=' + CAST(@R3b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: (duplicate of TEST 3) lake reassigned as mouth for a river
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @River4 uniqueidentifier = NEWID();
    DECLARE @Mouth4 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@River4, 2, N'River', 'UTRV5');
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Mouth4, 1, N'Lake', 'UTRV6');
    UPDATE Tributaries SET [lake_id] = @Mouth4
        WHERE lake_id = @River4 AND main_lake_id = @River4 AND side = 32;
    EXEC sp_assign_border @lake_id = @River4;
    DECLARE @R4a int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@River4, 1, 256));
    DECLARE @R4b int = (SELECT COUNT(*) FROM dbo.fn_ViewTributary(@Mouth4, 1, 256));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4a = 1 AND @R4b = 1
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake reassigned as mouth for river';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: river=' + CAST(@R4a AS varchar) + ' mouth=' + CAST(@R4b AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
