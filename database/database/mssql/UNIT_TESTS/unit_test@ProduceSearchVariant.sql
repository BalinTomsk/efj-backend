SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.ProduceSearchVariant.
  Database may not be empty - relies on pre-existing water-body keyword data for variant counts.
  Transaction is rolled back at end (no-op, kept for structural consistency).

  TEST  1 - NULL request -> 0 rows
  TEST  2 - empty string request -> 0 rows
  TEST  3 - English: Lake Francis -> 144 variants incl. exact
  TEST  4 - single name: Francis -> 18 variants incl. exact
  TEST  5 - French: Lac Francis -> 144 variants incl. exact (irank=0)
  TEST  6 - triple: Lac Santa Francis -> exact variant present (irank=0)
  TEST  7 - quadra: Lac Santa Laperusa Francis -> exact variant present (irank=0)
  TEST  8 - Lac St. Francis -> exact variant + English "Santa Francis Lake" variant present
  TEST  9 - Lac Santa Francis -> exact variant + English "St. Francis Lake" variant present
  TEST 10 - Lac Santa Francis and St. Francis Lake both produce their own exact variant
  TEST 11 - Blackie's Lake -> exact variant + French "Lac Blackies" variant present
  TEST 12 - test river -> exact variant present
  TEST 13 - test Reservoir -> exact variant present
  TEST 14 - test Brook -> exact variant present
  TEST 15 - test Burn -> exact variant present
  TEST 16 - test Canal -> exact variant present
  TEST 17 - test Channel -> exact variant present
  TEST 18 - test Creek -> exact variant present
  TEST 19 - test Ocean -> exact variant present
  TEST 20 - test Pond -> exact variant present
  TEST 21 - test River -> exact variant present
  TEST 22 - test Run -> exact variant present
  TEST 23 - test Strait -> exact variant present
  TEST 24 - test Stream -> exact variant present
  TEST 25 - test Sea -> exact variant present
  TEST 26 - bare guid -> exact variant present
  TEST 27 - bare guid (LIKE match) -> exact variant present
  TEST 28 - "A" Lake (double-quoted) -> both quoted and unquoted variants present
  TEST 29 - 'A' Lake (single-quoted) -> both quoted and unquoted variants present
  TEST 30 - North Sigma River -> "Sigma River" variant present
  TEST 31 - Ha! Ha! Lake -> "Ha Ha Lake" (punctuation-stripped) variant present
  TEST 32 - Humber River -> exact variant present
  TEST 33 - Naftel's Creek -> exact variant present
  TEST 34 - West Little White River -> exact variant present
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl1 TABLE (line sysname, irank int); INSERT INTO @Tbl1 SELECT * FROM dbo.ProduceSearchVariant(NULL);
    DECLARE @R1 int = (SELECT COUNT(*) FROM @Tbl1);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1 = 0 PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL request returned 0 rows';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@R1 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl2 TABLE (line sysname, irank int); INSERT INTO @Tbl2 SELECT * FROM dbo.ProduceSearchVariant('');
    DECLARE @R2 int = (SELECT COUNT(*) FROM @Tbl2);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2 = 0 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty string request returned 0 rows';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@R2 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl3 TABLE (line sysname, irank int); INSERT INTO @Tbl3 SELECT * FROM dbo.ProduceSearchVariant(N'Lake Francis');
    DECLARE @R3a int = (SELECT COUNT(*) FROM @Tbl3), @R3b int = (SELECT COUNT(*) FROM @Tbl3 WHERE line = N'Lake Francis');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3a = 144 AND @R3b = 1 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lake Francis -> 144 variants incl. exact';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R3a AS varchar) + ' exact=' + CAST(@R3b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl4 TABLE (line sysname, irank int); INSERT INTO @Tbl4 SELECT * FROM dbo.ProduceSearchVariant(N'Francis');
    DECLARE @R4a int = (SELECT COUNT(*) FROM @Tbl4), @R4b int = (SELECT COUNT(*) FROM @Tbl4 WHERE line = N'Francis');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4a = 18 AND @R4b = 1 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Francis -> 18 variants incl. exact';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R4a AS varchar) + ' exact=' + CAST(@R4b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl5 TABLE (line sysname, irank int); INSERT INTO @Tbl5 SELECT * FROM dbo.ProduceSearchVariant(N'Lac Francis');
    DECLARE @R5a int = (SELECT COUNT(*) FROM @Tbl5), @R5b int = (SELECT COUNT(*) FROM @Tbl5 WHERE line = N'Lac Francis' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R5a = 144 AND @R5b = 1 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac Francis -> 144 variants incl. exact';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R5a AS varchar) + ' exact=' + CAST(@R5b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl6 TABLE (line sysname, irank int); INSERT INTO @Tbl6 SELECT * FROM dbo.ProduceSearchVariant(N'Lac Santa Francis');
    DECLARE @R6 int = (SELECT COUNT(*) FROM @Tbl6 WHERE line = N'Lac Santa Francis' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R6 = 1 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac Santa Francis exact variant present';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R6 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl7 TABLE (line sysname, irank int); INSERT INTO @Tbl7 SELECT * FROM dbo.ProduceSearchVariant(N'Lac Santa Laperusa Francis');
    DECLARE @R7 int = (SELECT COUNT(*) FROM @Tbl7 WHERE line = N'Lac Santa Laperusa Francis' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R7 = 1 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac Santa Laperusa Francis exact variant present';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R7 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl8 TABLE (line sysname, irank int); INSERT INTO @Tbl8 SELECT * FROM dbo.ProduceSearchVariant(N'Lac St. Francis');
    DECLARE @R8a int = (SELECT COUNT(*) FROM @Tbl8 WHERE line = N'Lac St. Francis' AND irank = 0);
    DECLARE @R8b int = (SELECT COUNT(*) FROM @Tbl8 WHERE line = N'Santa Francis Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R8a = 1 AND @R8b = 1 PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac St. Francis exact + Santa Francis Lake variants present';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: exact=' + CAST(@R8a AS varchar) + ' other=' + CAST(@R8b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl9 TABLE (line sysname, irank int); INSERT INTO @Tbl9 SELECT * FROM dbo.ProduceSearchVariant(N'Lac Santa Francis');
    DECLARE @R9a int = (SELECT COUNT(*) FROM @Tbl9 WHERE line = N'Lac Santa Francis' AND irank = 0);
    DECLARE @R9b int = (SELECT COUNT(*) FROM @Tbl9 WHERE line = N'St. Francis Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R9a = 1 AND @R9b = 1 PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Lac Santa Francis exact + St. Francis Lake variants present';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: exact=' + CAST(@R9a AS varchar) + ' other=' + CAST(@R9b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl10a TABLE (line sysname, irank int); INSERT INTO @Tbl10a SELECT * FROM dbo.ProduceSearchVariant(N'Lac Santa Francis');
    DECLARE @Tbl10b TABLE (line sysname, irank int); INSERT INTO @Tbl10b SELECT * FROM dbo.ProduceSearchVariant(N'St. Francis Lake');
    DECLARE @R10a int = (SELECT COUNT(*) FROM @Tbl10a WHERE line = N'Lac Santa Francis' AND irank = 0);
    DECLARE @R10b int = (SELECT COUNT(*) FROM @Tbl10b WHERE line = N'St. Francis Lake' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R10a = 1 AND @R10b = 1 PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: both inputs produce their own exact variant';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: a=' + CAST(@R10a AS varchar) + ' b=' + CAST(@R10b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl11 TABLE (line sysname, irank int); INSERT INTO @Tbl11 SELECT * FROM dbo.ProduceSearchVariant(N'Blackie''s Lake');
    DECLARE @R11a int = (SELECT COUNT(*) FROM @Tbl11 WHERE line = N'Blackie''s Lake' AND irank = 0);
    DECLARE @R11b int = (SELECT COUNT(*) FROM @Tbl11 WHERE line = N'Lac Blackies' AND irank > 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R11a = 1 AND @R11b = 1 PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Blackie''s Lake exact + Lac Blackies variants present';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: exact=' + CAST(@R11a AS varchar) + ' french=' + CAST(@R11b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl12 TABLE (line sysname, irank int); INSERT INTO @Tbl12 SELECT * FROM dbo.ProduceSearchVariant(N'test river');
    DECLARE @R12 int = (SELECT COUNT(*) FROM @Tbl12 WHERE line = N'test river' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R12 = 1 PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test river exact variant present';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R12 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl13 TABLE (line sysname, irank int); INSERT INTO @Tbl13 SELECT * FROM dbo.ProduceSearchVariant(N'test Reservoir');
    DECLARE @R13 int = (SELECT COUNT(*) FROM @Tbl13 WHERE line = N'test Reservoir' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R13 = 1 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Reservoir exact variant present';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R13 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl14 TABLE (line sysname, irank int); INSERT INTO @Tbl14 SELECT * FROM dbo.ProduceSearchVariant(N'test Brook');
    DECLARE @R14 int = (SELECT COUNT(*) FROM @Tbl14 WHERE line = N'test Brook' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R14 = 1 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Brook exact variant present';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R14 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl15 TABLE (line sysname, irank int); INSERT INTO @Tbl15 SELECT * FROM dbo.ProduceSearchVariant(N'test Burn');
    DECLARE @R15 int = (SELECT COUNT(*) FROM @Tbl15 WHERE line = N'test Burn' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R15 = 1 PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Burn exact variant present';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R15 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl16 TABLE (line sysname, irank int); INSERT INTO @Tbl16 SELECT * FROM dbo.ProduceSearchVariant(N'test Canal');
    DECLARE @R16 int = (SELECT COUNT(*) FROM @Tbl16 WHERE line = N'test Canal' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R16 = 1 PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Canal exact variant present';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R16 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl17 TABLE (line sysname, irank int); INSERT INTO @Tbl17 SELECT * FROM dbo.ProduceSearchVariant(N'test Channel');
    DECLARE @R17 int = (SELECT COUNT(*) FROM @Tbl17 WHERE line = N'test Channel' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R17 = 1 PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Channel exact variant present';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R17 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl18 TABLE (line sysname, irank int); INSERT INTO @Tbl18 SELECT * FROM dbo.ProduceSearchVariant(N'test Creek');
    DECLARE @R18 int = (SELECT COUNT(*) FROM @Tbl18 WHERE line = N'test Creek' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R18 = 1 PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Creek exact variant present';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R18 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl19 TABLE (line sysname, irank int); INSERT INTO @Tbl19 SELECT * FROM dbo.ProduceSearchVariant(N'test Ocean');
    DECLARE @R19 int = (SELECT COUNT(*) FROM @Tbl19 WHERE line = N'test Ocean' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R19 = 1 PRINT 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Ocean exact variant present';
    ELSE PRINT 'TEST 19 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R19 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl20 TABLE (line sysname, irank int); INSERT INTO @Tbl20 SELECT * FROM dbo.ProduceSearchVariant(N'test Pond');
    DECLARE @R20 int = (SELECT COUNT(*) FROM @Tbl20 WHERE line = N'test Pond' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R20 = 1 PRINT 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Pond exact variant present';
    ELSE PRINT 'TEST 20 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R20 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl21 TABLE (line sysname, irank int); INSERT INTO @Tbl21 SELECT * FROM dbo.ProduceSearchVariant(N'test River');
    DECLARE @R21 int = (SELECT COUNT(*) FROM @Tbl21 WHERE line = N'test River' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R21 = 1 PRINT 'TEST 21 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test River exact variant present';
    ELSE PRINT 'TEST 21 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R21 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl22 TABLE (line sysname, irank int); INSERT INTO @Tbl22 SELECT * FROM dbo.ProduceSearchVariant(N'test Run');
    DECLARE @R22 int = (SELECT COUNT(*) FROM @Tbl22 WHERE line = N'test Run' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R22 = 1 PRINT 'TEST 22 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Run exact variant present';
    ELSE PRINT 'TEST 22 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R22 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl23 TABLE (line sysname, irank int); INSERT INTO @Tbl23 SELECT * FROM dbo.ProduceSearchVariant(N'test Strait');
    DECLARE @R23 int = (SELECT COUNT(*) FROM @Tbl23 WHERE line = N'test Strait' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R23 = 1 PRINT 'TEST 23 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Strait exact variant present';
    ELSE PRINT 'TEST 23 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R23 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl24 TABLE (line sysname, irank int); INSERT INTO @Tbl24 SELECT * FROM dbo.ProduceSearchVariant(N'test Stream');
    DECLARE @R24 int = (SELECT COUNT(*) FROM @Tbl24 WHERE line = N'test Stream' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R24 = 1 PRINT 'TEST 24 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Stream exact variant present';
    ELSE PRINT 'TEST 24 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R24 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl25 TABLE (line sysname, irank int); INSERT INTO @Tbl25 SELECT * FROM dbo.ProduceSearchVariant(N'test Sea');
    DECLARE @R25 int = (SELECT COUNT(*) FROM @Tbl25 WHERE line = N'test Sea' AND irank = 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R25 = 1 PRINT 'TEST 25 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: test Sea exact variant present';
    ELSE PRINT 'TEST 25 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R25 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl26 TABLE (line sysname, irank int); INSERT INTO @Tbl26 SELECT * FROM dbo.ProduceSearchVariant('5AE76765-D052-11D8-92E2-080020A0F4C9');
    DECLARE @R26 int = (SELECT COUNT(*) FROM @Tbl26 WHERE line = '5AE76765-D052-11D8-92E2-080020A0F4C9');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R26 = 1 PRINT 'TEST 26 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: bare guid exact variant present';
    ELSE PRINT 'TEST 26 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R26 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl27 TABLE (line sysname, irank int); INSERT INTO @Tbl27 SELECT * FROM dbo.ProduceSearchVariant('5AE76765-D052-11D8-92E2-080020A0F4C9');
    DECLARE @R27 int = (SELECT COUNT(*) FROM @Tbl27 WHERE line LIKE '5AE76765-D052-11D8-92E2-080020A0F4C9');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R27 = 1 PRINT 'TEST 27 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: bare guid (LIKE match) exact variant present';
    ELSE PRINT 'TEST 27 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R27 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl28 TABLE (line sysname, irank int); INSERT INTO @Tbl28 SELECT * FROM dbo.ProduceSearchVariant(N'"A" Lake');
    DECLARE @R28a int = (SELECT COUNT(*) FROM @Tbl28 WHERE line LIKE N'A Lake');
    DECLARE @R28b int = (SELECT COUNT(*) FROM @Tbl28 WHERE line LIKE N'"A" Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R28a = 1 AND @R28b = 1 PRINT 'TEST 28 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: "A" Lake produced both quoted and unquoted variants';
    ELSE PRINT 'TEST 28 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: unquoted=' + CAST(@R28a AS varchar) + ' quoted=' + CAST(@R28b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl29 TABLE (line sysname, irank int); INSERT INTO @Tbl29 SELECT * FROM dbo.ProduceSearchVariant(N'''A'' Lake');
    DECLARE @R29a int = (SELECT COUNT(*) FROM @Tbl29 WHERE line LIKE N'A Lake');
    DECLARE @R29b int = (SELECT COUNT(*) FROM @Tbl29 WHERE line LIKE N'''A'' Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R29a = 1 AND @R29b = 1 PRINT 'TEST 29 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: ''A'' Lake produced both quoted and unquoted variants';
    ELSE PRINT 'TEST 29 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: unquoted=' + CAST(@R29a AS varchar) + ' quoted=' + CAST(@R29b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl30 TABLE (line sysname, irank int); INSERT INTO @Tbl30 SELECT * FROM dbo.ProduceSearchVariant(N'North Sigma River');
    DECLARE @R30 int = (SELECT COUNT(*) FROM @Tbl30 WHERE line LIKE N'Sigma River');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R30 = 1 PRINT 'TEST 30 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: North Sigma River -> Sigma River variant present';
    ELSE PRINT 'TEST 30 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R30 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl31 TABLE (line sysname, irank int); INSERT INTO @Tbl31 SELECT * FROM dbo.ProduceSearchVariant(N'Ha! Ha! Lake');
    DECLARE @R31 int = (SELECT COUNT(*) FROM @Tbl31 WHERE line LIKE N'Ha Ha Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R31 = 1 PRINT 'TEST 31 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Ha! Ha! Lake -> punctuation-stripped variant present';
    ELSE PRINT 'TEST 31 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R31 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl32 TABLE (line sysname, irank int); INSERT INTO @Tbl32 SELECT * FROM dbo.ProduceSearchVariant(N'Humber River');
    DECLARE @R32 int = (SELECT COUNT(*) FROM @Tbl32 WHERE line LIKE N'Humber River');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R32 = 1 PRINT 'TEST 32 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Humber River exact variant present';
    ELSE PRINT 'TEST 32 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R32 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl33 TABLE (line sysname, irank int); INSERT INTO @Tbl33 SELECT * FROM dbo.ProduceSearchVariant(N'Naftel''s Creek');
    DECLARE @R33 int = (SELECT COUNT(*) FROM @Tbl33 WHERE line LIKE N'Naftel''s Creek');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R33 = 1 PRINT 'TEST 33 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Naftel''s Creek exact variant present';
    ELSE PRINT 'TEST 33 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R33 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @Tbl34 TABLE (line sysname, irank int); INSERT INTO @Tbl34 SELECT * FROM dbo.ProduceSearchVariant(N'West Little White River');
    DECLARE @R34 int = (SELECT COUNT(*) FROM @Tbl34 WHERE line LIKE N'West Little White River');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R34 = 1 PRINT 'TEST 34 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: West Little White River exact variant present';
    ELSE PRINT 'TEST 34 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R34 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
