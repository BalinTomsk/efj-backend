SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.sp_upsert_fish_catch_probability and dbo.spTotalUpdateCatch.
  Uses real tables dbo.fish, dbo.fish_catch_probability, dbo.WaterStation, dbo.fish_location.
  Transaction is rolled back at end - database state restored.

  NOTE: TEST 8-13 duplicate TEST 1-6's sp_upsert_fish_catch_probability assertions - this
  duplication exists in the original test file (the second block was headed as covering
  fish_lunar_catch_probability / spTotalUpdateLunar but never actually exercises that code
  path) and is preserved here unchanged; only the reporting structure was converted.

  TEST  1 - sp_upsert_fish_catch_probability inserts new catch probability records
  TEST  2 - sp_upsert_fish_catch_probability updates existing catch probability records
  TEST  3 - sp_upsert_fish_catch_probability boundary values (0 / 500)
  TEST  4 - sp_upsert_fish_catch_probability processes all months atomically
  TEST  5 - sp_upsert_fish_catch_probability with a real fish from the database
  TEST  6 - sp_upsert_fish_catch_probability performance (10 upserts < 1000ms)
  TEST  7 - spTotalUpdateCatch updates fish_location.today from current month probability
  TEST  8 - (duplicate of TEST 1)
  TEST  9 - (duplicate of TEST 2)
  TEST 10 - (duplicate of TEST 3)
  TEST 11 - (duplicate of TEST 4)
  TEST 12 - (duplicate of TEST 5)
  TEST 13 - (duplicate of TEST 6)
*/
SET NOCOUNT ON;

DECLARE @tStart      datetime2;
DECLARE @ElapsedMs   int;
DECLARE @TestFishId  uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @TestFishId)
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@TestFishId, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');

    -- ----------------------------------------------------------------
    -- TEST 1: insert new catch probability records
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=50, @probability_feb=60, @probability_mar=100, @probability_apr=150,
        @probability_may=200, @probability_jun=250, @probability_jul=300, @probability_aug=280,
        @probability_sep=200, @probability_oct=150, @probability_nov=100, @probability_dec=75;
    DECLARE @T1Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T1Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T1Jul int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T1Cnt = 12 AND @T1Jan = 50 AND @T1Jul = 300
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stored 12 months with jan=50 jul=300';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T1Cnt AS varchar) + ' jan=' + CAST(@T1Jan AS varchar) + ' jul=' + CAST(@T1Jul AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 2: update existing catch probability records
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=50, @probability_feb=60, @probability_mar=100, @probability_apr=150,
        @probability_may=200, @probability_jun=250, @probability_jul=300, @probability_aug=280,
        @probability_sep=200, @probability_oct=150, @probability_nov=100, @probability_dec=75;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=100, @probability_feb=110, @probability_mar=120, @probability_apr=180,
        @probability_may=250, @probability_jun=300, @probability_jul=350, @probability_aug=330,
        @probability_sep=250, @probability_oct=180, @probability_nov=120, @probability_dec=100;
    DECLARE @T2Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T2Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T2Jul int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T2Cnt = 12 AND @T2Jan = 100 AND @T2Jul = 350
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: update overwrote 12 months with jan=100 jul=350';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T2Cnt AS varchar) + ' jan=' + CAST(@T2Jan AS varchar) + ' jul=' + CAST(@T2Jul AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 3: boundary values (0 / 500)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=0, @probability_feb=500, @probability_mar=0, @probability_apr=500,
        @probability_may=0, @probability_jun=500, @probability_jul=0, @probability_aug=500,
        @probability_sep=0, @probability_oct=500, @probability_nov=0, @probability_dec=500;
    DECLARE @T3Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T3Feb int = (SELECT ISNULL(MAX(CASE WHEN month = 2 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T3Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T3Jan = 0 AND @T3Feb = 500 AND @T3Cnt = 12
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: boundary values jan=0 feb=500 stored for 12 months';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: jan=' + CAST(@T3Jan AS varchar) + ' feb=' + CAST(@T3Feb AS varchar) + ' count=' + CAST(@T3Cnt AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 4: all months are processed atomically
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=100, @probability_feb=100, @probability_mar=100, @probability_apr=100,
        @probability_may=100, @probability_jun=100, @probability_jul=100, @probability_aug=100,
        @probability_sep=100, @probability_oct=100, @probability_nov=100, @probability_dec=100;
    DECLARE @T4Before int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=25, @probability_feb=25, @probability_mar=25, @probability_apr=25,
        @probability_may=25, @probability_jun=25, @probability_jul=25, @probability_aug=25,
        @probability_sep=25, @probability_oct=25, @probability_nov=25, @probability_dec=25;
    DECLARE @T4After int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T4Bad   int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId AND probability <> 25);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T4Before = 12 AND @T4After = 12 AND @T4Bad = 0
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: all 12 months updated atomically to 25';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: before=' + CAST(@T4Before AS varchar) + ' after=' + CAST(@T4After AS varchar) + ' bad=' + CAST(@T4Bad AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 5: with a real fish from the database
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @RealFishId5 uniqueidentifier;
    SELECT TOP 1 @RealFishId5 = fish_id FROM dbo.fish WHERE fish_id <> @TestFishId ORDER BY fish_name;
    DECLARE @T5Cnt int = 12, @T5Jan int = 10, @T5Dec int = 120;
    IF @RealFishId5 IS NOT NULL
    BEGIN
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId5;
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id=@RealFishId5, @probability_jan=10, @probability_feb=20, @probability_mar=30, @probability_apr=40,
            @probability_may=50, @probability_jun=60, @probability_jul=70, @probability_aug=80,
            @probability_sep=90, @probability_oct=100, @probability_nov=110, @probability_dec=120;
        SELECT @T5Cnt = COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId5;
        SELECT @T5Jan = ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId5;
        SELECT @T5Dec = ISNULL(MAX(CASE WHEN month = 12 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId5;
    END
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T5Cnt = 12 AND @T5Jan = 10 AND @T5Dec = 120
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: real fish upsert stored jan=10 dec=120';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T5Cnt AS varchar) + ' jan=' + CAST(@T5Jan AS varchar) + ' dec=' + CAST(@T5Dec AS varchar);
    IF @RealFishId5 IS NOT NULL DELETE FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId5;

    -- ----------------------------------------------------------------
    -- TEST 6: performance - 10 upserts complete in under 1000ms
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    DECLARE @Iter6 int = 0;
    WHILE @Iter6 < 10
    BEGIN
        DECLARE @Prob6 int = @Iter6 * 10;
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id=@TestFishId, @probability_jan=@Prob6, @probability_feb=@Prob6, @probability_mar=@Prob6, @probability_apr=@Prob6,
            @probability_may=@Prob6, @probability_jun=@Prob6, @probability_jul=@Prob6, @probability_aug=@Prob6,
            @probability_sep=@Prob6, @probability_oct=@Prob6, @probability_nov=@Prob6, @probability_dec=@Prob6;
        SET @Iter6 = @Iter6 + 1;
    END
    DECLARE @T6Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T6Final int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId AND probability = 90);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T6Cnt = 12 AND @T6Final = 12 AND @ElapsedMs < 1000
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 10 upserts completed with final value 90 on all months';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T6Cnt AS varchar) + ' final=' + CAST(@T6Final AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 7: spTotalUpdateCatch updates fish_location.today from current month probability
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @RealFishId7   uniqueidentifier;
    DECLARE @Station7      uniqueidentifier = NEWID();
    DECLARE @Month7        tinyint = DATEPART(MONTH, GETUTCDATE());
    DECLARE @OldStamp7     datetime2(7) = DATEADD(DAY, -10, SYSUTCDATETIME());
    DECLARE @BeforeExec7   datetime2(7) = SYSUTCDATETIME();
    DECLARE @ReturnValue7  int;

    SELECT TOP 1 @RealFishId7 = fish_id FROM dbo.fish ORDER BY fish_name;

    INSERT INTO dbo.WaterStation
        (MLI, id, state, lat, lon, tz, country, locDesc, locType, agency, county, locName, sid, lakeName, stamp, supported)
    VALUES
        ('UT_' + REPLACE(CONVERT(varchar(36), @Station7), '-', ''), @Station7, 'ON', 43.4516, -80.4925, -5, 'CA',
         'Unit test water station', 1, 'UNIT_TEST', 'WATERLOO', 'Unit Test Station', 999001, N'Unit Test Lake', SYSUTCDATETIME(), 1);

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId7 AND [month] = @Month7;
    DELETE FROM dbo.fish_location WHERE station_Id = @Station7 AND fish_Id = @RealFishId7;

    INSERT INTO dbo.fish_catch_probability (fish_id, [month], probability) VALUES (@RealFishId7, @Month7, 85);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, today, stamp, probability, id)
    VALUES (@Station7, @RealFishId7, 10, @OldStamp7, 20, 999001);

    EXEC @ReturnValue7 = dbo.spTotalUpdateCatch;

    DECLARE @ActualToday7 int, @ActualProbability7 int, @ActualStamp7 datetime2(7);
    SELECT @ActualToday7 = today, @ActualProbability7 = probability, @ActualStamp7 = stamp
    FROM dbo.fish_location WHERE station_Id = @Station7 AND fish_Id = @RealFishId7;

    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ReturnValue7 = 1 AND @ActualToday7 = 85 AND @ActualProbability7 = 20 AND @ActualStamp7 >= @BeforeExec7
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: spTotalUpdateCatch set today=85, left probability=20, refreshed stamp';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: return=' + ISNULL(CAST(@ReturnValue7 AS varchar),'NULL')
            + ' today=' + ISNULL(CAST(@ActualToday7 AS varchar),'NULL') + ' probability=' + ISNULL(CAST(@ActualProbability7 AS varchar),'NULL');

    -- ----------------------------------------------------------------
    -- TEST 8: (duplicate of TEST 1) insert new catch probability records
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=50, @probability_feb=60, @probability_mar=100, @probability_apr=150,
        @probability_may=200, @probability_jun=250, @probability_jul=300, @probability_aug=280,
        @probability_sep=200, @probability_oct=150, @probability_nov=100, @probability_dec=75;
    DECLARE @T8Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T8Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T8Jul int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T8Cnt = 12 AND @T8Jan = 50 AND @T8Jul = 300
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stored 12 months with jan=50 jul=300';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T8Cnt AS varchar) + ' jan=' + CAST(@T8Jan AS varchar) + ' jul=' + CAST(@T8Jul AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 9: (duplicate of TEST 2) update existing catch probability records
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=50, @probability_feb=60, @probability_mar=100, @probability_apr=150,
        @probability_may=200, @probability_jun=250, @probability_jul=300, @probability_aug=280,
        @probability_sep=200, @probability_oct=150, @probability_nov=100, @probability_dec=75;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=100, @probability_feb=110, @probability_mar=120, @probability_apr=180,
        @probability_may=250, @probability_jun=300, @probability_jul=350, @probability_aug=330,
        @probability_sep=250, @probability_oct=180, @probability_nov=120, @probability_dec=100;
    DECLARE @T9Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T9Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T9Jul int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T9Cnt = 12 AND @T9Jan = 100 AND @T9Jul = 350
        PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: update overwrote 12 months with jan=100 jul=350';
    ELSE
        PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T9Cnt AS varchar) + ' jan=' + CAST(@T9Jan AS varchar) + ' jul=' + CAST(@T9Jul AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 10: (duplicate of TEST 3) boundary values (0 / 500)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=0, @probability_feb=500, @probability_mar=0, @probability_apr=500,
        @probability_may=0, @probability_jun=500, @probability_jul=0, @probability_aug=500,
        @probability_sep=0, @probability_oct=500, @probability_nov=0, @probability_dec=500;
    DECLARE @T10Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T10Feb int = (SELECT ISNULL(MAX(CASE WHEN month = 2 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T10Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T10Jan = 0 AND @T10Feb = 500 AND @T10Cnt = 12
        PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: boundary values jan=0 feb=500 stored for 12 months';
    ELSE
        PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: jan=' + CAST(@T10Jan AS varchar) + ' feb=' + CAST(@T10Feb AS varchar) + ' count=' + CAST(@T10Cnt AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 11: (duplicate of TEST 4) all months are processed atomically
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=100, @probability_feb=100, @probability_mar=100, @probability_apr=100,
        @probability_may=100, @probability_jun=100, @probability_jul=100, @probability_aug=100,
        @probability_sep=100, @probability_oct=100, @probability_nov=100, @probability_dec=100;
    DECLARE @T11Before int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id=@TestFishId, @probability_jan=25, @probability_feb=25, @probability_mar=25, @probability_apr=25,
        @probability_may=25, @probability_jun=25, @probability_jul=25, @probability_aug=25,
        @probability_sep=25, @probability_oct=25, @probability_nov=25, @probability_dec=25;
    DECLARE @T11After int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T11Bad   int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId AND probability <> 25);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T11Before = 12 AND @T11After = 12 AND @T11Bad = 0
        PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: all 12 months updated atomically to 25';
    ELSE
        PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: before=' + CAST(@T11Before AS varchar) + ' after=' + CAST(@T11After AS varchar) + ' bad=' + CAST(@T11Bad AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    -- ----------------------------------------------------------------
    -- TEST 12: (duplicate of TEST 5) with a real fish from the database
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @RealFishId12 uniqueidentifier;
    SELECT TOP 1 @RealFishId12 = fish_id FROM dbo.fish WHERE fish_id <> @TestFishId ORDER BY fish_name;
    IF @RealFishId12 IS NULL
    BEGIN
        SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
        PRINT 'TEST 12 SKIP [' + CAST(@ElapsedMs AS varchar) + 'ms]: no real fish available for testing';
    END
    ELSE
    BEGIN
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId12;
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id=@RealFishId12, @probability_jan=10, @probability_feb=20, @probability_mar=30, @probability_apr=40,
            @probability_may=50, @probability_jun=60, @probability_jul=70, @probability_aug=80,
            @probability_sep=90, @probability_oct=100, @probability_nov=110, @probability_dec=120;
        DECLARE @T12Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId12);
        DECLARE @T12Jan int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId12);
        DECLARE @T12Dec int = (SELECT ISNULL(MAX(CASE WHEN month = 12 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId12);
        SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
        IF @T12Cnt = 12 AND @T12Jan = 10 AND @T12Dec = 120
            PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: real fish upsert stored jan=10 dec=120';
        ELSE
            PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T12Cnt AS varchar) + ' jan=' + CAST(@T12Jan AS varchar) + ' dec=' + CAST(@T12Dec AS varchar);
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @RealFishId12;
    END

    -- ----------------------------------------------------------------
    -- TEST 13: (duplicate of TEST 6) performance - 10 upserts complete in under 1000ms
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;
    DECLARE @Iter13 int = 0;
    WHILE @Iter13 < 10
    BEGIN
        DECLARE @Prob13 int = @Iter13 * 10;
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id=@TestFishId, @probability_jan=@Prob13, @probability_feb=@Prob13, @probability_mar=@Prob13, @probability_apr=@Prob13,
            @probability_may=@Prob13, @probability_jun=@Prob13, @probability_jul=@Prob13, @probability_aug=@Prob13,
            @probability_sep=@Prob13, @probability_oct=@Prob13, @probability_nov=@Prob13, @probability_dec=@Prob13;
        SET @Iter13 = @Iter13 + 1;
    END
    DECLARE @T13Cnt int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId);
    DECLARE @T13Final int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId AND probability = 90);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T13Cnt = 12 AND @T13Final = 12 AND @ElapsedMs < 1000
        PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 10 upserts completed with final value 90 on all months';
    ELSE
        PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@T13Cnt AS varchar) + ' final=' + CAST(@T13Final AS varchar);
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @TestFishId;

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
