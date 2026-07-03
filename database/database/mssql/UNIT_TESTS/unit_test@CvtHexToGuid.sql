/*
  Unit tests for dbo.fn_CvtHexToGuid.
  No table fixtures needed - purely a scalar conversion function.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST  1 - convert 00000000-0000-0000-0000-000000000000 (all zeros)
  TEST  2 - convert all-ones hex string
  TEST  3 - convert all-f's hex string
  TEST  4 - convert mixed-digit hex string
  TEST  5 - convert upper-case random hex string
  TEST  6 - convert lower-case random hex string
  TEST  7 - convert with a leading space
  TEST  8 - convert with a trailing space
  TEST  9 - convert with surrounding figure brackets
  TEST 10 - invalid characters (non-hex) -> NULL
  TEST 11 - space-only string -> NULL
  TEST 12 - empty string -> NULL
  TEST 13 - NULL input -> NULL
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @Result    uniqueidentifier;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: convert 00000000-0000-0000-0000-000000000000
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('00000000000000000000000000000000');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '00000000-0000-0000-0000-000000000000'
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the all-zero hex string';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 2: convert all-ones hex string
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('111111111111111111111111111111111');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '11111111-1111-1111-1111-1111111111111'
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the all-ones hex string';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 3: convert all-f's hex string
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('fffffffffffffffffffffffffffffffff');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 'ffffffff-ffff-ffff-ffff-fffffffffffff'
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the all-f''s hex string';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 4: convert mixed-digit hex string
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('12345678901234567890abcdef0123456');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '12345678-9012-3456-7890-abcdef0123456'
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the mixed-digit hex string';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 5: convert upper-case random hex string
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('5BCF4766DC35435C97B1733FD8675049');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5BCF4766-DC35-435C-97B1-733FD8675049'
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the upper-case hex string';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 6: convert lower-case random hex string
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('5bcf4766dc35435c97b1733fd8675049');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5bcf4766-dc35-435c-97b1-733fd8675049'
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted the lower-case hex string';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 7: convert with a leading space
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid(' 5bcf4766dc35435c97b1733fd8675049');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5bcf4766-dc35-435c-97b1-733fd8675049'
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted with a leading space';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 8: convert with a trailing space
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('5bcf4766dc35435c97b1733fd8675049 ');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5bcf4766-dc35-435c-97b1-733fd8675049'
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted with a trailing space';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 9: convert with surrounding figure brackets
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid(' {5bcf4766dc35435c97b1733fd8675049} ');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = '5bcf4766-dc35-435c-97b1-733fd8675049'
        PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: converted with surrounding figure brackets';
    ELSE
        PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@Result AS char(36)), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 10: invalid characters (non-hex) -> NULL
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('4766+dc35(435c)97b1');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL
        PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: invalid characters returned NULL';
    ELSE
        PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS char(36));

    -- ----------------------------------------------------------------
    -- TEST 11: space-only string -> NULL
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('    ');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL
        PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: space-only string returned NULL';
    ELSE
        PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS char(36));

    -- ----------------------------------------------------------------
    -- TEST 12: empty string -> NULL
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid('');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL
        PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty string returned NULL';
    ELSE
        PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS char(36));

    -- ----------------------------------------------------------------
    -- TEST 13: NULL input -> NULL
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_CvtHexToGuid(NULL);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL
        PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL input returned NULL';
    ELSE
        PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS char(36));

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
