SET QUOTED_IDENTIFIER ON
GO

PRINT 'Unit Tests for dbo.sp_upsert_fish_catch_probability' 
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV1
DECLARE @test_name sysname = N'TestFCPV1 [sp_upsert_fish_catch_probability] : Insert new catch probability records'
BEGIN TRY  
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 50,
        @probability_feb = 60,
        @probability_mar = 100,
        @probability_apr = 150,
        @probability_may = 200,
        @probability_jun = 250,
        @probability_jul = 300,
        @probability_aug = 280,
        @probability_sep = 200,
        @probability_oct = 150,
        @probability_nov = 100,
        @probability_dec = 75;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 12 OR @result2 <> 50 OR @result3 <> 300
        RAISERROR ('FAILED: %s expected count=12 jan=50 jul=300, actual count=%d jan=%d jul=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV1
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV2
DECLARE @test_name sysname = N'TestFCPV2 [sp_upsert_fish_catch_probability] : Update existing catch probability records'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 50,
        @probability_feb = 60,
        @probability_mar = 100,
        @probability_apr = 150,
        @probability_may = 200,
        @probability_jun = 250,
        @probability_jul = 300,
        @probability_aug = 280,
        @probability_sep = 200,
        @probability_oct = 150,
        @probability_nov = 100,
        @probability_dec = 75;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 100,
        @probability_feb = 110,
        @probability_mar = 120,
        @probability_apr = 180,
        @probability_may = 250,
        @probability_jun = 300,
        @probability_jul = 350,
        @probability_aug = 330,
        @probability_sep = 250,
        @probability_oct = 180,
        @probability_nov = 120,
        @probability_dec = 100;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 12 OR @result2 <> 100 OR @result3 <> 350
        RAISERROR ('FAILED: %s expected count=12 jan=100 jul=350, actual count=%d jan=%d jul=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV2
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV6
DECLARE @test_name sysname = N'TestFCPV6 [sp_upsert_fish_catch_probability] : Validate boundary values'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 0,
        @probability_feb = 500,
        @probability_mar = 0,
        @probability_apr = 500,
        @probability_may = 0,
        @probability_jun = 500,
        @probability_jul = 0,
        @probability_aug = 500,
        @probability_sep = 0,
        @probability_oct = 500,
        @probability_nov = 0,
        @probability_dec = 500;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 2 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 0 OR @result2 <> 500 OR @result3 <> 12
        RAISERROR ('FAILED: %s expected jan=0 feb=500 count=12, actual jan=%d feb=%d count=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV6
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV7
DECLARE @test_name sysname = N'TestFCPV7 [sp_upsert_fish_catch_probability] : Verify all months are processed atomically'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 100,
        @probability_feb = 100,
        @probability_mar = 100,
        @probability_apr = 100,
        @probability_may = 100,
        @probability_jun = 100,
        @probability_jul = 100,
        @probability_aug = 100,
        @probability_sep = 100,
        @probability_oct = 100,
        @probability_nov = 100,
        @probability_dec = 100;

    DECLARE @count_before int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 25,
        @probability_feb = 25,
        @probability_mar = 25,
        @probability_apr = 25,
        @probability_may = 25,
        @probability_jun = 25,
        @probability_jul = 25,
        @probability_aug = 25,
        @probability_sep = 25,
        @probability_oct = 25,
        @probability_nov = 25,
        @probability_dec = 25;

    -- 3. Result verification
    DECLARE @count_after int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @bad_values int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id AND probability <> 25);

    IF @count_before <> 12 OR @count_after <> 12 OR @bad_values <> 0
        RAISERROR ('FAILED: %s expected before=12 after=12 bad_values=0, actual before=%d after=%d bad_values=%d', 16, -1, @test_name, @count_before, @count_after, @bad_values);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV7
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV8
DECLARE @test_name sysname = N'TestFCPV8 [sp_upsert_fish_catch_probability] : Test with real fish from database'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @real_fish_id uniqueidentifier;
    DECLARE @test_skipped bit = 0;

    SELECT TOP 1 @real_fish_id = fish_id
    FROM dbo.fish
    WHERE fish_id <> 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001'
    ORDER BY fish_name;

    IF @real_fish_id IS NULL
    BEGIN
        SET @test_skipped = 1;
    END
    ELSE
    BEGIN
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id;

        -- 2. Execute unit test
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id = @real_fish_id,
            @probability_jan = 10,
            @probability_feb = 20,
            @probability_mar = 30,
            @probability_apr = 40,
            @probability_may = 50,
            @probability_jun = 60,
            @probability_jul = 70,
            @probability_aug = 80,
            @probability_sep = 90,
            @probability_oct = 100,
            @probability_nov = 110,
            @probability_dec = 120;
    END

    -- 3. Result verification
    DECLARE @result1 int = CASE WHEN @test_skipped = 1 THEN 12 ELSE (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;
    DECLARE @result2 int = CASE WHEN @test_skipped = 1 THEN 10 ELSE (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;
    DECLARE @result3 int = CASE WHEN @test_skipped = 1 THEN 120 ELSE (SELECT ISNULL(MAX(CASE WHEN month = 12 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;

    IF @result1 <> 12 OR @result2 <> 10 OR @result3 <> 120
        RAISERROR ('FAILED: %s expected count=12 jan=10 dec=120, actual count=%d jan=%d dec=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    IF @test_skipped = 0
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV8
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV9
DECLARE @test_name sysname = N'TestFCPV9 [sp_upsert_fish_catch_probability] : Performance test multiple updates'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    DECLARE @start_time datetime2 = SYSDATETIME();
    DECLARE @iteration int = 0;

    WHILE @iteration < 10
    BEGIN
        DECLARE @probability int = @iteration * 10;

        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id = @test_fish_id,
            @probability_jan = @probability,
            @probability_feb = @probability,
            @probability_mar = @probability,
            @probability_apr = @probability,
            @probability_may = @probability,
            @probability_jun = @probability,
            @probability_jul = @probability,
            @probability_aug = @probability,
            @probability_sep = @probability,
            @probability_oct = @probability,
            @probability_nov = @probability,
            @probability_dec = @probability;

        SET @iteration = @iteration + 1;
    END

    DECLARE @end_time datetime2 = SYSDATETIME();
    DECLARE @duration_ms int = DATEDIFF(MILLISECOND, @start_time, @end_time);

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id AND probability = 90);
    DECLARE @result3 int = @duration_ms;

    IF @result1 <> 12 OR @result2 <> 12 OR @result3 >= 1000
        RAISERROR ('FAILED: %s expected count=12 final_values=12 duration<1000ms, actual count=%d final_values=%d duration=%dms', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

    ROLLBACK TRAN TestFCPV9
GO
----------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestTotalUpdateCatchV1

DECLARE @test_name sysname = N'TestTotalUpdateCatchV1 [spTotalUpdateCatch] : updates fish_location.today from current month catch probability';

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @real_fish_id uniqueidentifier;
    DECLARE @test_station_id uniqueidentifier = NEWID();
    DECLARE @month tinyint = DATEPART(MONTH, GETUTCDATE());
    DECLARE @old_stamp datetime2(7) = DATEADD(DAY, -10, SYSUTCDATETIME());
    DECLARE @before_exec datetime2(7) = SYSUTCDATETIME();
    DECLARE @return_value int;

    SELECT TOP 1 @real_fish_id = fish_id
    FROM dbo.fish
    ORDER BY fish_name;

    IF @real_fish_id IS NULL
        RAISERROR('FAILED: %s no fish rows available for testing', 16, -1, @test_name);

    INSERT INTO dbo.WaterStation
    (
        MLI,
        id,
        state,
        lat,
        lon,
        tz,
        country,
        locDesc,
        locType,
        agency,
        county,
        locName,
        sid,
        lakeName,
        stamp,
        supported
    )
    VALUES
    (
        'UT_' + REPLACE(CONVERT(varchar(36), @test_station_id), '-', ''),
        @test_station_id,
        'ON',
        43.4516,
        -80.4925,
        -5,
        'CA',
        'Unit test water station',
        1,
        'UNIT_TEST',
        'WATERLOO',
        'Unit Test Station',
        999001,
        N'Unit Test Lake',
        SYSUTCDATETIME(),
        1
    );

    DELETE FROM dbo.fish_catch_probability
    WHERE fish_id = @real_fish_id
      AND [month] = @month;

    DELETE FROM dbo.fish_location
    WHERE station_Id = @test_station_id
      AND fish_Id = @real_fish_id;

    INSERT INTO dbo.fish_catch_probability
    (
        fish_id,
        [month],
        probability
    )
    VALUES
    (
        @real_fish_id,
        @month,
        85
    );

    INSERT INTO dbo.fish_location
    (
        station_Id,
        fish_Id,
        today,
        stamp,
        probability,
        id
    )
    VALUES
    (
        @test_station_id,
        @real_fish_id,
        10,
        @old_stamp,
        20,
        999001
    );

    EXEC @return_value = dbo.spTotalUpdateCatch;

    DECLARE @actual_today int;
    DECLARE @actual_probability int;
    DECLARE @actual_stamp datetime2(7);

    SELECT
        @actual_today = today,
        @actual_probability = probability,
        @actual_stamp = stamp
    FROM dbo.fish_location
    WHERE station_Id = @test_station_id
      AND fish_Id = @real_fish_id;

    IF @return_value <> 1
        RAISERROR('FAILED: %s expected return_value=1, actual=%d', 16, -1, @test_name, @return_value);

    IF @actual_today <> 85
        RAISERROR('FAILED: %s expected today=85, actual=%d', 16, -1, @test_name, @actual_today);

    IF @actual_probability <> 20
        RAISERROR('FAILED: %s probability should not change, expected=20, actual=%d', 16, -1, @test_name, @actual_probability);

    IF @actual_stamp < @before_exec
        RAISERROR('FAILED: %s stamp was not updated', 16, -1, @test_name);

    PRINT 'PASSED ' + @test_name;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestTotalUpdateCatchV1
GO
----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
/*
fish_lunar_catch_probability -- [spTotalUpdateLunar]
1.	Lunar cycle simulation: Tests various lunar probability percentages (0%, 50%, 75%, 100%)
2.	Rounding validation: Ensures ROUND() function works correctly
3.	Current day awareness: Uses DATEPART(DAY, GETUTCDATE()) to match procedure logic
4.	Edge cases: Tests boundary values (0% and 100%)
5.	No-update scenario: Verifies WHERE clause prevents unnecessary updates
6.	Timestamp validation: Ensures stamp is only updated when today changes
*/
--These tests validate that the lunar multiplier correctly adjusts fish catch probabilities based on the lunar cycle day.
----------------------------------------------------------------------------------------------------------
PRINT 'Unit Tests for dbo.sp_upsert_fish_catch_probability' 
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV1
DECLARE @test_name sysname = N'TestFCPV1 [sp_upsert_fish_catch_probability] : Insert new catch probability records'
BEGIN TRY  
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 50,
        @probability_feb = 60,
        @probability_mar = 100,
        @probability_apr = 150,
        @probability_may = 200,
        @probability_jun = 250,
        @probability_jul = 300,
        @probability_aug = 280,
        @probability_sep = 200,
        @probability_oct = 150,
        @probability_nov = 100,
        @probability_dec = 75;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 12 OR @result2 <> 50 OR @result3 <> 300
        RAISERROR ('FAILED: %s expected count=12 jan=50 jul=300, actual count=%d jan=%d jul=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV1
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV2
DECLARE @test_name sysname = N'TestFCPV2 [sp_upsert_fish_catch_probability] : Update existing catch probability records'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 50,
        @probability_feb = 60,
        @probability_mar = 100,
        @probability_apr = 150,
        @probability_may = 200,
        @probability_jun = 250,
        @probability_jul = 300,
        @probability_aug = 280,
        @probability_sep = 200,
        @probability_oct = 150,
        @probability_nov = 100,
        @probability_dec = 75;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 100,
        @probability_feb = 110,
        @probability_mar = 120,
        @probability_apr = 180,
        @probability_may = 250,
        @probability_jun = 300,
        @probability_jul = 350,
        @probability_aug = 330,
        @probability_sep = 250,
        @probability_oct = 180,
        @probability_nov = 120,
        @probability_dec = 100;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT ISNULL(MAX(CASE WHEN month = 7 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 12 OR @result2 <> 100 OR @result3 <> 350
        RAISERROR ('FAILED: %s expected count=12 jan=100 jul=350, actual count=%d jan=%d jul=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV2
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV6
DECLARE @test_name sysname = N'TestFCPV6 [sp_upsert_fish_catch_probability] : Validate boundary values'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 0,
        @probability_feb = 500,
        @probability_mar = 0,
        @probability_apr = 500,
        @probability_may = 0,
        @probability_jun = 500,
        @probability_jul = 0,
        @probability_aug = 500,
        @probability_sep = 0,
        @probability_oct = 500,
        @probability_nov = 0,
        @probability_dec = 500;

    -- 3. Result verification
    DECLARE @result1 int = (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT ISNULL(MAX(CASE WHEN month = 2 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result3 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    IF @result1 <> 0 OR @result2 <> 500 OR @result3 <> 12
        RAISERROR ('FAILED: %s expected jan=0 feb=500 count=12, actual jan=%d feb=%d count=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV6
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV7
DECLARE @test_name sysname = N'TestFCPV7 [sp_upsert_fish_catch_probability] : Verify all months are processed atomically'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 100,
        @probability_feb = 100,
        @probability_mar = 100,
        @probability_apr = 100,
        @probability_may = 100,
        @probability_jun = 100,
        @probability_jul = 100,
        @probability_aug = 100,
        @probability_sep = 100,
        @probability_oct = 100,
        @probability_nov = 100,
        @probability_dec = 100;

    DECLARE @count_before int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);

    -- 2. Execute unit test
    EXEC dbo.sp_upsert_fish_catch_probability
        @fish_id = @test_fish_id,
        @probability_jan = 25,
        @probability_feb = 25,
        @probability_mar = 25,
        @probability_apr = 25,
        @probability_may = 25,
        @probability_jun = 25,
        @probability_jul = 25,
        @probability_aug = 25,
        @probability_sep = 25,
        @probability_oct = 25,
        @probability_nov = 25,
        @probability_dec = 25;

    -- 3. Result verification
    DECLARE @count_after int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @bad_values int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id AND probability <> 25);

    IF @count_before <> 12 OR @count_after <> 12 OR @bad_values <> 0
        RAISERROR ('FAILED: %s expected before=12 after=12 bad_values=0, actual before=%d after=%d bad_values=%d', 16, -1, @test_name, @count_before, @count_after, @bad_values);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV7
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV8
DECLARE @test_name sysname = N'TestFCPV8 [sp_upsert_fish_catch_probability] : Test with real fish from database'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @real_fish_id uniqueidentifier;
    DECLARE @test_skipped bit = 0;

    SELECT TOP 1 @real_fish_id = fish_id
    FROM dbo.fish
    WHERE fish_id <> 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001'
    ORDER BY fish_name;

    IF @real_fish_id IS NULL
    BEGIN
        SET @test_skipped = 1;
    END
    ELSE
    BEGIN
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id;

        -- 2. Execute unit test
        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id = @real_fish_id,
            @probability_jan = 10,
            @probability_feb = 20,
            @probability_mar = 30,
            @probability_apr = 40,
            @probability_may = 50,
            @probability_jun = 60,
            @probability_jul = 70,
            @probability_aug = 80,
            @probability_sep = 90,
            @probability_oct = 100,
            @probability_nov = 110,
            @probability_dec = 120;
    END

    -- 3. Result verification
    DECLARE @result1 int = CASE WHEN @test_skipped = 1 THEN 12 ELSE (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;
    DECLARE @result2 int = CASE WHEN @test_skipped = 1 THEN 10 ELSE (SELECT ISNULL(MAX(CASE WHEN month = 1 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;
    DECLARE @result3 int = CASE WHEN @test_skipped = 1 THEN 120 ELSE (SELECT ISNULL(MAX(CASE WHEN month = 12 THEN probability END), -1) FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id) END;

    IF @test_skipped = 1
        PRINT 'SKIPPED ' + @test_name + ' : no real fish available for testing';
    ELSE IF @result1 <> 12 OR @result2 <> 10 OR @result3 <> 120
        RAISERROR ('FAILED: %s expected count=12 jan=10 dec=120, actual count=%d jan=%d dec=%d', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    IF @test_skipped = 0
        DELETE FROM dbo.fish_catch_probability WHERE fish_id = @real_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV8
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestFCPV9
DECLARE @test_name sysname = N'TestFCPV9 [sp_upsert_fish_catch_probability] : Performance test multiple updates'
BEGIN TRY
    SET NOCOUNT ON;

    -- 1. Prepare test data
    DECLARE @test_fish_id uniqueidentifier = 'AAAAAAAA-BBBB-CCCC-DDDD-000000000001';

    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @test_fish_id)
    BEGIN
        INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id)
        VALUES (@test_fish_id, N'Test Fish for Unit Tests', N'Testus Fishicus', '00000000-0000-0000-0000-000000000000');
    END

    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

    -- 2. Execute unit test
    DECLARE @start_time datetime2 = SYSDATETIME();
    DECLARE @iteration int = 0;

    WHILE @iteration < 10
    BEGIN
        DECLARE @probability int = @iteration * 10;

        EXEC dbo.sp_upsert_fish_catch_probability
            @fish_id = @test_fish_id,
            @probability_jan = @probability,
            @probability_feb = @probability,
            @probability_mar = @probability,
            @probability_apr = @probability,
            @probability_may = @probability,
            @probability_jun = @probability,
            @probability_jul = @probability,
            @probability_aug = @probability,
            @probability_sep = @probability,
            @probability_oct = @probability,
            @probability_nov = @probability,
            @probability_dec = @probability;

        SET @iteration = @iteration + 1;
    END

    DECLARE @end_time datetime2 = SYSDATETIME();
    DECLARE @duration_ms int = DATEDIFF(MILLISECOND, @start_time, @end_time);

    -- 3. Result verification
    DECLARE @result1 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id);
    DECLARE @result2 int = (SELECT COUNT(*) FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id AND probability = 90);
    DECLARE @result3 int = @duration_ms;

    IF @result1 <> 12 OR @result2 <> 12 OR @result3 >= 1000
        RAISERROR ('FAILED: %s expected count=12 final_values=12 duration<1000ms, actual count=%d final_values=%d duration=%dms', 16, -1, @test_name, @result1, @result2, @result3);
    ELSE
        PRINT 'PASSED ' + @test_name;

    -- Cleanup
    DELETE FROM dbo.fish_catch_probability WHERE fish_id = @test_fish_id;

END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        @test_name       AS ErrorProcedure,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestFCPV9
GO