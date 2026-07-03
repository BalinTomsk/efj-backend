SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.ProduceWBVariant.
  Database may not be empty - relies on pre-existing water-body keyword data for variant counts.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST 1 - West Little White River -> 15 variants incl. "West Little White"
  TEST 2 - Naftel's Creek -> 3 variants incl. "Naftel's"
  TEST 3 - Casselman's Creek -> 3 variants incl. "Casselman's"
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl1 TABLE (line sysname, irank int, id int); INSERT INTO @Tbl1 SELECT * FROM dbo.ProduceWBVariant(N'West Little White River');
    DECLARE @R1a int = (SELECT COUNT(*) FROM @Tbl1), @R1b int = (SELECT COUNT(*) FROM @Tbl1 WHERE line LIKE N'West Little White');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1a = 15 AND @R1b = 1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: West Little White River -> 15 variants incl. West Little White';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R1a AS varchar) + ' match=' + CAST(@R1b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl2 TABLE (line sysname, irank int, id int); INSERT INTO @Tbl2 SELECT * FROM dbo.ProduceWBVariant(N'Naftel''s Creek');
    DECLARE @R2a int = (SELECT COUNT(*) FROM @Tbl2), @R2b int = (SELECT COUNT(*) FROM @Tbl2 WHERE line LIKE N'Naftel''s');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2a = 3 AND @R2b = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Naftel''s Creek -> 3 variants incl. Naftel''s';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R2a AS varchar) + ' match=' + CAST(@R2b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl3 TABLE (line sysname, irank int, id int); INSERT INTO @Tbl3 SELECT * FROM dbo.ProduceWBVariant(N'Casselman''s Creek');
    DECLARE @R3a int = (SELECT COUNT(*) FROM @Tbl3), @R3b int = (SELECT COUNT(*) FROM @Tbl3 WHERE line LIKE N'Casselman''s');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3a = 3 AND @R3b = 1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Casselman''s Creek -> 3 variants incl. Casselman''s';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R3a AS varchar) + ' match=' + CAST(@R3b AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
