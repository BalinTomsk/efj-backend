SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.sp_upsert_fish_temperature_probability, dbo.sp_upsert_fish_oxygen_probability.
  Uses real tables dbo.fish, dbo.fish_Rule, dbo.real_interval, dbo.WaterStation,
  dbo.CurrentWaterState, dbo.fish_location - each test uses a fresh fish/station id and a
  unique mli value, so merging into one shared transaction does not create cross-test
  interference. Transaction is rolled back at end - database state restored.

  TEST 1 - temperature at optimal -> 100% coefficient
  TEST 2 - temperature outside viable range -> 0% coefficient
  TEST 3 - temperature at minimum threshold -> 80% coefficient
  TEST 4 - missing temperature data -> no update (stays at prior value)
  TEST 5 - oxygen at optimal -> 100% coefficient
  TEST 6 - oxygen outside viable range -> 0% coefficient
  TEST 7 - oxygen at 90% zone
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: temperature at optimal
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId1 uniqueidentifier = NEWID();
    DECLARE @StationId1 uniqueidentifier = NEWID();
    DECLARE @RuleId1 uniqueidentifier;
    DECLARE @Mli1 varchar(64) = 'TEST_MLI_001';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId1, 'Test Fish 1', 'Testus fishus1', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId1 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId1 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId1, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId1, @Mli1, 'Test Lake', 1, 'Test Station 1', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@Mli1, 15.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId1, @FishId1, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_temperature_probability;
    DECLARE @R1 int; SELECT @R1 = today FROM dbo.fish_location WHERE station_Id = @StationId1 AND fish_Id = @FishId1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1 = 100 PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: temperature at optimal -> 100% coefficient';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 100, got ' + CAST(ISNULL(@R1, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: temperature outside viable range
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId2 uniqueidentifier = NEWID();
    DECLARE @StationId2 uniqueidentifier = NEWID();
    DECLARE @RuleId2 uniqueidentifier;
    DECLARE @Mli2 varchar(64) = 'TEST_MLI_002';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId2, 'Test Fish 2', 'Testus fishus2', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId2 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId2 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId2, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId2, @Mli2, 'Test Lake 2', 1, 'Test Station 2', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@Mli2, 5.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId2, @FishId2, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_temperature_probability;
    DECLARE @R2 int; SELECT @R2 = today FROM dbo.fish_location WHERE station_Id = @StationId2 AND fish_Id = @FishId2;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2 = 0 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: temperature outside viable range -> 0% coefficient';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(ISNULL(@R2, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: temperature at minimum threshold
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId3 uniqueidentifier = NEWID();
    DECLARE @StationId3 uniqueidentifier = NEWID();
    DECLARE @RuleId3 uniqueidentifier;
    DECLARE @Mli3 varchar(64) = 'TEST_MLI_003';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId3, 'Test Fish 3', 'Testus fishus3', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId3 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId3 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId3, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId3, @Mli3, 'Test Lake 3', 1, 'Test Station 3', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@Mli3, 10.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId3, @FishId3, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_temperature_probability;
    DECLARE @R3 int; SELECT @R3 = today FROM dbo.fish_location WHERE station_Id = @StationId3 AND fish_Id = @FishId3;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3 = 80 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: temperature at minimum threshold -> 80% coefficient';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 80, got ' + CAST(ISNULL(@R3, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: missing temperature data
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId4 uniqueidentifier = NEWID();
    DECLARE @StationId4 uniqueidentifier = NEWID();
    DECLARE @RuleId4 uniqueidentifier;
    DECLARE @Mli4 varchar(64) = 'TEST_MLI_004';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId4, 'Test Fish 4', 'Testus fishus4', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId4 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId4 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId4, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId4, @Mli4, 'Test Lake 4', 1, 'Test Station 4', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@Mli4, NULL, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId4, @FishId4, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_temperature_probability;
    DECLARE @R4 int; SELECT @R4 = today FROM dbo.fish_location WHERE station_Id = @StationId4 AND fish_Id = @FishId4;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4 = 100 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: missing temperature data -> no update';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 100, got ' + CAST(ISNULL(@R4, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 5: oxygen at optimal
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId5 uniqueidentifier = NEWID();
    DECLARE @StationId5 uniqueidentifier = NEWID();
    DECLARE @RuleId5 uniqueidentifier;
    DECLARE @Mli5 varchar(64) = 'TEST_MLI_005';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId5, 'Test Fish 5', 'Testus fishus5', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId5 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId5 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId5, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId5, @Mli5, 'Test Lake 5', 1, 'Test Station 5', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@Mli5, 8.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId5, @FishId5, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    DECLARE @R5 int; SELECT @R5 = today FROM dbo.fish_location WHERE station_Id = @StationId5 AND fish_Id = @FishId5;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R5 = 100 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: oxygen at optimal -> 100% coefficient';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 100, got ' + CAST(ISNULL(@R5, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 6: oxygen outside viable range
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId6 uniqueidentifier = NEWID();
    DECLARE @StationId6 uniqueidentifier = NEWID();
    DECLARE @RuleId6 uniqueidentifier;
    DECLARE @Mli6 varchar(64) = 'TEST_MLI_006';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId6, 'Test Fish 6', 'Testus fishus6', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId6 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId6 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId6, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId6, @Mli6, 'Test Lake 6', 1, 'Test Station 6', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@Mli6, 4.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId6, @FishId6, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    DECLARE @R6 int; SELECT @R6 = today FROM dbo.fish_location WHERE station_Id = @StationId6 AND fish_Id = @FishId6;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R6 = 0 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: oxygen outside viable range -> 0% coefficient';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(ISNULL(@R6, -999) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 7: oxygen at 90% zone
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @FishId7 uniqueidentifier = NEWID();
    DECLARE @StationId7 uniqueidentifier = NEWID();
    DECLARE @RuleId7 uniqueidentifier;
    DECLARE @Mli7 varchar(64) = 'TEST_MLI_007';
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@FishId7, 'Test Fish 7', 'Testus fishus7', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @RuleId7 = id FROM dbo.fish_Rule WHERE fish_Id = @FishId7 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@RuleId7, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@StationId7, @Mli7, 'Test Lake 7', 1, 'Test Station 7', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@Mli7, 7.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@StationId7, @FishId7, 100, 100, GETUTCDATE());
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    DECLARE @R7 int; SELECT @R7 = today FROM dbo.fish_location WHERE station_Id = @StationId7 AND fish_Id = @FishId7;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R7 = 90 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: oxygen at 90% zone';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 90, got ' + CAST(ISNULL(@R7, -999) AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
