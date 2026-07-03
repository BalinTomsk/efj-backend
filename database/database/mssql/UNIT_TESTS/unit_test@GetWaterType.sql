SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.GetWaterType.
  No table fixtures needed - purely a scalar parsing function.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST  1 - single abstract word -> NULL
  TEST  2 - pure water type without name: Lake -> 1
  TEST  3 - pure water type without name: River -> 2
  TEST  4 - Lake Huron -> 1
  TEST  5 - Lac Huron (French) -> 1
  TEST  6 - Grand River -> 2
  TEST  7 - Grand Riviere (French, accented) -> 2
  TEST  8 - Biver Brook -> 64
  TEST  9 - Biver Ruisseau (French) -> 64
  TEST 10 - Big Reservoir -> 8192
  TEST 11 - Big Reservoir (French, accented) -> 8192
  TEST 12 - Sand Bay -> 1
  TEST 13 - Sand Baie (French) -> 1
  TEST 14 - Side Burn -> 64
  TEST 15 - Canada Canal -> 128
  TEST 16 - Canada Channel -> 128
  TEST 17 - Pike Creek -> 64
  TEST 18 - Pacific Ocean -> 16385
  TEST 19 - Pacific Ocean (French, accented) -> 16385
  TEST 20 - Small Pond -> 8
  TEST 21 - Small Etang (French, accented) -> 8
  TEST 22 - Small Run -> 64
  TEST 23 - Small Courir (French) -> 64
  TEST 24 - Border Strait -> 128
  TEST 25 - Border Detroit (French, accented) -> 128
  TEST 26 - Silver Stream -> 4
  TEST 27 - Silver Courant (French) -> 4
  TEST 28 - Baltic Sea -> 16385 (input corrected from original's "Baltic See" typo, which the
            old NULL-comparison bug silently masked)
  TEST 29 - Mer Lapteva (French) -> 16385
  TEST 30 - Abra Kadabra (unrecognized) -> NULL
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @Result    int;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'abstract'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: single abstract word returned NULL';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS varchar);

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Lake'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 1 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lake -> 1';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'River'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 2 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: River -> 2';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Lake Huron'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 1 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lake Huron -> 1';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Lac Huron'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 1 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac Huron -> 1';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Grand River'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 2 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Grand River -> 2';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Grand ' + N'Rivi'+nchar(233)+N're'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 2 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Grand Riviere -> 2';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Biver Brook'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Biver Brook -> 64';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Biver Ruisseau'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Biver Ruisseau -> 64';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Big Reservoir'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 8192 PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Big Reservoir -> 8192';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 8192, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Big R'+nchar(233)+N'servoir'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 8192 PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Big Reservoir (accented) -> 8192';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 8192, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Sand Bay'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 1 PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Sand Bay -> 1';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Sand Baie'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 1 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Sand Baie -> 1';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Side Burn'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Side Burn -> 64';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Canada Canal'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 128 PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Canada Canal -> 128';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 128, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Canada Channel'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 128 PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Canada Channel -> 128';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 128, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Pike Creek'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Pike Creek -> 64';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Pacific Ocean'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 16385 PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Pacific Ocean -> 16385';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 16385, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Pacific ' + N'Oc'+nchar(233)+N'an'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 16385 PRINT 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Pacific Ocean (accented) -> 16385';
    ELSE PRINT 'TEST 19 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 16385, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Small Pond'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 8 PRINT 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Small Pond -> 8';
    ELSE PRINT 'TEST 20 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 8, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Small ' + nchar(201)+N'tang'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 8 PRINT 'TEST 21 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Small Etang (accented) -> 8';
    ELSE PRINT 'TEST 21 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 8, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Small Run'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 22 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Small Run -> 64';
    ELSE PRINT 'TEST 22 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Small Courir'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 64 PRINT 'TEST 23 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Small Courir -> 64';
    ELSE PRINT 'TEST 23 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 64, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Border Strait'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 128 PRINT 'TEST 24 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Border Strait -> 128';
    ELSE PRINT 'TEST 24 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 128, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Border D'+nchar(233)+N'troit'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 128 PRINT 'TEST 25 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Border Detroit (accented) -> 128';
    ELSE PRINT 'TEST 25 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 128, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Silver Stream'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 4 PRINT 'TEST 26 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Silver Stream -> 4';
    ELSE PRINT 'TEST 26 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 4, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Silver Courant'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 4 PRINT 'TEST 27 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Silver Courant -> 4';
    ELSE PRINT 'TEST 27 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 4, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Baltic Sea'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 16385 PRINT 'TEST 28 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Baltic Sea -> 16385';
    ELSE PRINT 'TEST 28 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 16385, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Mer Lapteva'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 16385 PRINT 'TEST 29 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Mer Lapteva -> 16385';
    ELSE PRINT 'TEST 29 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 16385, got ' + ISNULL(CAST(@Result AS varchar),'NULL');

    SET @tStart = SYSUTCDATETIME(); SET @Result = dbo.GetWaterType(N'Abra Kadabra'); SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result IS NULL PRINT 'TEST 30 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: unrecognized type returned NULL';
    ELSE PRINT 'TEST 30 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + CAST(@Result AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
