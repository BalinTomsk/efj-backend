SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.SearchLakeList.
  Uses real table dbo.lake. Each test deletes the fixture lake_name values used anywhere
  in this file before inserting its own fixture, so accumulation across tests sharing one
  transaction cannot inflate another test's exact-count assertion. Transaction is rolled
  back at end - database state restored.

  TEST  1 - NULL parameter -> 0 rows
  TEST  2 - empty parameter -> 0 rows
  TEST  3 - find: test lake
  TEST  4 - fail to find: test lake (only "test river" exists)
  TEST  5 - find: French spelling of test lake (Lac test)
  TEST  6 - find: all 4 variants of test lake
  TEST  7 - find by lake guid (dashed)
  TEST  8 - find by lake hex guid (no dashes)
  TEST  9 - find single-name lake by a double-name search
  TEST 10 - find double-name lake by a single-name search
  TEST 11 - "Ha! Ha! Lake" is NOT matched by "Ha Lake"
  TEST 12 - find: River Lake
  TEST 13 - find: Lac gold
  TEST 14 - lake with 2 photos in lake_image is NOT duplicated (vw_lake join regression)
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @FixtureNames TABLE (n sysname);
INSERT INTO @FixtureNames (n) VALUES
    (N'test lake'), (N'test river'), (N'Lac test'), (N'test Lac'), (N'test Lake'), (N'Lake test'),
    (N'Single Lake'), (N'Great Double Lake'), (N'Ha! Ha! Lake'), (N'River Lake'), (N'Lac gold'),
    (N'Test Multi Photo Lake');

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('test lake', 1);
    DECLARE @Tbl1 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl1 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(NULL);
    DECLARE @R1 int = (SELECT COUNT(*) FROM @Tbl1);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1 = 0 PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL parameter returned 0 rows';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@R1 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('test lake', 1);
    DECLARE @Tbl2 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl2 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList('');
    DECLARE @R2 int = (SELECT COUNT(*) FROM @Tbl2);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2 = 0 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty parameter returned 0 rows';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@R2 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('test lake', 1);
    DECLARE @Tbl3 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl3 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'test lake');
    DECLARE @R3 int = (SELECT COUNT(*) FROM @Tbl3);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3 = 1 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found test lake';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R3 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('test river', 1);
    DECLARE @Tbl4 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl4 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'test lake');
    DECLARE @R4 int = (SELECT COUNT(*) FROM @Tbl4);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4 = 0 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: correctly failed to find test lake';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@R4 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Lid5 uniqueidentifier = NEWID();
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid5, 'Lac test', 1);
    DECLARE @Tbl5 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl5 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'test lake');
    DECLARE @R5 int = (SELECT COUNT(*) FROM @Tbl5);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R5 = 1 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found French spelling Lac test';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R5 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Lid6a uniqueidentifier = NEWID(), @Lid6b uniqueidentifier = NEWID(), @Lid6c uniqueidentifier = NEWID(), @Lid6d uniqueidentifier = NEWID();
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid6a, 'Lac test', 1);
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid6b, 'test Lac', 1);
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid6c, 'test Lake', 1);
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid6d, 'Lake test', 1);
    DECLARE @Tbl6 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl6 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'test lake');
    DECLARE @R6 int = (SELECT COUNT(*) FROM @Tbl6);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R6 = 4 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: all 4 variants of test lake found';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 4, got ' + CAST(@R6 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (lake_id, lake_name, locType) VALUES ('5AE76765-D052-11D8-92E2-080020A0F4C9', 'Lac test', 1);
    DECLARE @Tbl7 TABLE (lake_id uniqueidentifier NOT NULL PRIMARY KEY, lake_name sysname, locType int);
    INSERT INTO @Tbl7 (lake_id, lake_name, locType) SELECT lake_id, lake_name, locType FROM dbo.SearchLakeList(N'5AE76765-D052-11D8-92E2-080020A0F4C9');
    DECLARE @R7 int = (SELECT COUNT(*) FROM @Tbl7);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R7 = 1 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by dashed guid';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R7 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (lake_id, lake_name, locType) VALUES ('6BF87876-E163-22E9-A3F3-191131B1D5DA', 'Lac test2', 1);
    DECLARE @Tbl8 TABLE (lake_id uniqueidentifier NOT NULL PRIMARY KEY, lake_name sysname, locType int);
    INSERT INTO @Tbl8 (lake_id, lake_name, locType) SELECT lake_id, lake_name, locType FROM dbo.SearchLakeList(N'6bf87876e16322e9a3f3191131b1d5da');
    DECLARE @R8 int = (SELECT COUNT(*) FROM @Tbl8 WHERE lake_id = '6BF87876-E163-22E9-A3F3-191131B1D5DA');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R8 = 1 PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by bare hex guid';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R8 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('Single Lake', 1);
    DECLARE @Tbl9 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl9 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'Great Single Lake');
    DECLARE @R9a int = (SELECT COUNT(*) FROM @Tbl9), @R9b int = (SELECT COUNT(*) FROM @Tbl9 WHERE lake_name = 'Single Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R9a = 1 AND @R9b = 1 PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: single-name lake found via double-name search';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R9a AS varchar) + ' match=' + CAST(@R9b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    INSERT INTO lake (lake_name, locType) VALUES ('Great Double Lake', 1);
    DECLARE @Tbl10 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl10 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'Double Lake');
    DECLARE @R10a int = (SELECT COUNT(*) FROM @Tbl10), @R10b int = (SELECT COUNT(*) FROM @Tbl10 WHERE lake_name = 'Great Double Lake');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R10a = 1 AND @R10b = 1 PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: double-name lake found via single-name search';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R10a AS varchar) + ' match=' + CAST(@R10b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Dbname11 sysname = 'Ha! Ha! Lake';
    INSERT INTO lake (lake_name, locType) VALUES (@Dbname11, 1);
    DECLARE @Tbl11 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl11 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'Ha Lake') ORDER BY irank ASC;
    DECLARE @R11a int = (SELECT COUNT(*) FROM @Tbl11), @R11b int = (SELECT COUNT(*) FROM @Tbl11 WHERE lake_name = @Dbname11);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R11a = 0 AND @R11b = 0 PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Ha! Ha! Lake correctly NOT matched by Ha Lake';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R11a AS varchar) + ' match=' + CAST(@R11b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Dbname12 sysname = 'River Lake';
    INSERT INTO lake (lake_name, locType) VALUES (@Dbname12, 1);
    DECLARE @Tbl12 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl12 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'River Lake') ORDER BY irank ASC;
    DECLARE @R12a int = (SELECT COUNT(*) FROM @Tbl12), @R12b int = (SELECT COUNT(*) FROM @Tbl12 WHERE lake_name = @Dbname12);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R12a = 1 AND @R12b = 1 PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found River Lake';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R12a AS varchar) + ' match=' + CAST(@R12b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Dbname13 sysname = 'Lac gold';
    INSERT INTO lake (lake_name, locType) VALUES (@Dbname13, 1);
    DECLARE @Tbl13 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl13 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'Lac gold') ORDER BY irank ASC;
    DECLARE @R13a int = (SELECT COUNT(*) FROM @Tbl13), @R13b int = (SELECT COUNT(*) FROM @Tbl13 WHERE lake_name = @Dbname13);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R13a = 1 AND @R13b = 1 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found Lac gold';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R13a AS varchar) + ' match=' + CAST(@R13b AS varchar);

    -- Regression: vw_lake (which SearchLakeList is built on) must join only the single newest
    -- lake_image row per owner. lake_image is many-per-owner (photo gallery) — a lake with 2+
    -- photos previously came back once per photo (e.g. Guelph Lake showed twice in the editor
    -- search on 2026-07-04). Two photos for one lake here reproduces that exactly.
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM lake_image WHERE lake_image_ownerid IN (SELECT lake_id FROM lake JOIN @FixtureNames f ON f.n = lake.lake_name);
    DELETE t FROM Tributaries t JOIN lake l ON l.lake_id IN (t.lake_id, t.Main_Lake_id) JOIN @FixtureNames f ON f.n = l.lake_name;
    DELETE l FROM lake l JOIN @FixtureNames f ON f.n = l.lake_name;
    DECLARE @Lid14 uniqueidentifier = NEWID();
    INSERT INTO lake (Lake_id, lake_name, locType) VALUES (@Lid14, N'Test Multi Photo Lake', 1);
    INSERT INTO lake_image (lake_image_ownerid, lake_image_pic, lake_image_source, lake_image_author, lake_image_link, lake_image_hash, lake_image_stamp)
        VALUES (@Lid14, 0x01, N'src1', N'auth1', N'', CAST(NEWID() AS varbinary(256)), '2026-01-01');
    INSERT INTO lake_image (lake_image_ownerid, lake_image_pic, lake_image_source, lake_image_author, lake_image_link, lake_image_hash, lake_image_stamp)
        VALUES (@Lid14, 0x02, N'src2', N'auth2', N'', CAST(NEWID() AS varbinary(256)), '2026-01-02');
    DECLARE @Tbl14 TABLE (lake_name sysname, locType int);
    INSERT INTO @Tbl14 (lake_name, locType) SELECT lake_name, locType FROM dbo.SearchLakeList(N'Test Multi Photo Lake');
    DECLARE @R14 int = (SELECT COUNT(*) FROM @Tbl14);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R14 = 1 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake with 2 photos returned exactly once (not duplicated)';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@R14 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
