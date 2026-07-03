SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.NormalizeSearch.
  No table fixtures needed - purely a scalar parsing function.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST  1 - guid with spaces and figure brackets is unwrapped
  TEST  2 - NULL parameter -> NULL
  TEST  3 - empty parameter -> NULL
  TEST  4 - single-space parameter -> NULL
  TEST  5 - double-space parameter -> NULL
  TEST  6 - dot parameter -> NULL
  TEST  7 - filtered symbols only -> NULL
  TEST  8 - filtered symbols wrapping a guid -> guid extracted
  TEST  9 - valid lake name passes through unchanged
  TEST 10 - valid lake name with double space is collapsed to single space
  TEST 11 - valid name with a dot is preserved
  TEST 12 - valid name with a dash is preserved
  TEST 13 - valid French name with an accented e (é) is preserved
  TEST 14 - valid French name with a cedilla (ç) is preserved
  TEST 15 - valid French name with a diaeresis (ü) is preserved
  TEST 16 - valid French name with a circumflex (ê) is preserved
  TEST 17 - valid name with exclamation marks is preserved
  TEST 18 - valid French name with acute e (é) + grave e (è)... (unaccented lookalike) is preserved
  TEST 19 - valid French name with circumflex o (ô) is preserved
  TEST 20 - bare hex guid is converted to dashed uppercase guid
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @Result    nvarchar(255);

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(' {5bcf4766-dc35-435c-97b1-733fd8675049} '); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5bcf4766-dc35-435c-97b1-733fd8675049' PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: guid with spaces/brackets unwrapped';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(NULL); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL parameter returned NULL';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(''); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty parameter returned NULL';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(' '); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: single-space parameter returned NULL';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('  '); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: double-space parameter returned NULL';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('.'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: dot parameter returned NULL';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(',  ' + char(13) + char(10) + ' ){  }'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: filtered-symbols-only parameter returned NULL';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Result;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(',  ' + char(13) + char(10) + ' ){5BCF4766-DC35-435C-97B1-733FD8675049}'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5BCF4766-DC35-435C-97B1-733FD8675049' PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: guid extracted from filtered-symbols wrapper';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('Lake Huron'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 'Lake Huron' PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: valid name passed through unchanged';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('Lake  Huron'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 'Lake Huron' PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: double space collapsed to single space';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('Lake St. Francis'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 'Lake St. Francis' PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: dot preserved';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch('A-H Lake'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 'A-H Lake' PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: dash preserved';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Lac Hatché'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Lac Hatché' PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: accented e (Hatché) preserved';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Lac Hameçon'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Lac Hameçon' PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: cedilla (Hameçon) preserved';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Lac Haüy'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Lac Haüy' PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: diaeresis (Haüy) preserved';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Troisième lac Haut'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Troisième lac Haut' PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: circumflex/grave accents (Troisième) preserved';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Lac Ha! Ha!'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Lac Ha! Ha!' PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: exclamation marks preserved';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Étang Coté'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Étang Coté' PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: accented E and acute e (Étang Coté) preserved';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'Étang Côté'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = N'Étang Côté' PRINT 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: circumflex o (Côté) preserved';
    ELSE PRINT 'TEST 19 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.NormalizeSearch(N'5ae76765d05211d892e2080020a0f4c9'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5AE76765-D052-11D8-92E2-080020A0F4C9' PRINT 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: bare hex guid converted to dashed uppercase guid';
    ELSE PRINT 'TEST 20 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Result, 'NULL');

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
