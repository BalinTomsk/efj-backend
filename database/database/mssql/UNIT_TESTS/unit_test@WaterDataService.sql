-- ============================================================================
-- 2. RUN UNIT TESTS
-- ============================================================================
SET NOCOUNT ON;

PRINT 'Unit tests for fish probability';
PRINT '-----------------------------------------------------------------------------------------------------------------------------';
PRINT '-----------------------------------------------------------------------------------------------------------------------------';

-- Test 1: Temperature at optimal
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id UNIQUEIDENTIFIER;
    DECLARE @test_mli VARCHAR(64) = 'TEST_MLI_001';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id, 'Test Fish 1', 'Testus fishus1', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id, @test_mli, 'Test Lake', 1, 'Test Station 1', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@test_mli, 15.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id, @test_fish_id, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_temperature_probability;
    
    DECLARE @result_probability INT;
    SELECT @result_probability = today FROM dbo.fish_location WHERE station_Id = @test_station_id AND fish_Id = @test_fish_id;
    
    IF @result_probability = 100 PRINT 'PASSED Test1 [sp_upsert_fish_temperature_probability] Temperature at optimal (100% coefficient)';
    ELSE PRINT 'FAILED Test1 [sp_upsert_fish_temperature_probability] Expected 100, got ' + CAST(ISNULL(@result_probability, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test1 Error: ' + ERROR_MESSAGE(); END CATCH;
-------------------------------------------------------------------------------------------------------------------------
GO

-- Test 2: Temperature outside viable range
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id2 UNIQUEIDENTIFIER;
    DECLARE @test_mli2 VARCHAR(64) = 'TEST_MLI_002';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id2, 'Test Fish 2', 'Testus fishus2', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id2 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id2 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id2, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id2, @test_mli2, 'Test Lake 2', 1, 'Test Station 2', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@test_mli2, 5.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id2, @test_fish_id2, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_temperature_probability;
    
    DECLARE @result_probability2 INT;
    SELECT @result_probability2 = today FROM dbo.fish_location WHERE station_Id = @test_station_id2 AND fish_Id = @test_fish_id2;
    
    IF @result_probability2 = 0 PRINT 'PASSED Test2 [sp_upsert_fish_temperature_probability] Temperature outside viable range (0% coefficient)';
    ELSE PRINT 'FAILED Test2 [sp_upsert_fish_temperature_probability] Expected 0, got ' + CAST(ISNULL(@result_probability2, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test2 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------

-- Test 3: Temperature at minimum threshold
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id3 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id3 UNIQUEIDENTIFIER;
    DECLARE @test_mli3 VARCHAR(64) = 'TEST_MLI_003';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id3, 'Test Fish 3', 'Testus fishus3', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id3 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id3 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id3, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id3, @test_mli3, 'Test Lake 3', 1, 'Test Station 3', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@test_mli3, 10.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id3, @test_fish_id3, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_temperature_probability;
    
    DECLARE @result_probability3 INT;
    SELECT @result_probability3 = today FROM dbo.fish_location WHERE station_Id = @test_station_id3 AND fish_Id = @test_fish_id3;
    
    IF @result_probability3 = 80 PRINT 'PASSED Test3 [sp_upsert_fish_temperature_probability] Temperature at minimum threshold (80% coefficient)';
    ELSE PRINT 'FAILED Test3 [sp_upsert_fish_temperature_probability] Expected 80, got ' + CAST(ISNULL(@result_probability3, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test3 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------

-- Test 4: Missing temperature data
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id4 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id4 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id4 UNIQUEIDENTIFIER;
    DECLARE @test_mli4 VARCHAR(64) = 'TEST_MLI_004';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id4, 'Test Fish 4', 'Testus fishus4', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id4 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id4 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id4, 17, 10.0, 12.0, 15.0, 18.0, 20.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id4, @test_mli4, 'Test Lake 4', 1, 'Test Station 4', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, temperature, stamp, iterstamp, sid)
    VALUES (@test_mli4, NULL, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id4, @test_fish_id4, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_temperature_probability;
    
    DECLARE @result_probability4 INT;
    SELECT @result_probability4 = today FROM dbo.fish_location WHERE station_Id = @test_station_id4 AND fish_Id = @test_fish_id4;
    
    IF @result_probability4 = 100 PRINT 'PASSED Test4 [sp_upsert_fish_temperature_probability] Missing temperature data (no update)';
    ELSE PRINT 'FAILED Test4 [sp_upsert_fish_temperature_probability] Expected 100, got ' + CAST(ISNULL(@result_probability4, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test4 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------

-- Test 5: Oxygen at optimal
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id5 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id5 UNIQUEIDENTIFIER;
    DECLARE @test_mli5 VARCHAR(64) = 'TEST_MLI_005';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id5, 'Test Fish 5', 'Testus fishus5', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id5 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id5 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id5, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id5, @test_mli5, 'Test Lake 5', 1, 'Test Station 5', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@test_mli5, 8.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id5, @test_fish_id5, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    
    DECLARE @result_probability5 INT;
    SELECT @result_probability5 = today FROM dbo.fish_location WHERE station_Id = @test_station_id5 AND fish_Id = @test_fish_id5;
    
    IF @result_probability5 = 100 PRINT 'PASSED Test5 [sp_upsert_fish_oxygen_probability] Oxygen at optimal (100% coefficient)';
    ELSE PRINT 'FAILED Test5 [sp_upsert_fish_oxygen_probability] Expected 100, got ' + CAST(ISNULL(@result_probability5, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test5 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------

-- Test 6: Oxygen outside viable range
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id6 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id6 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id6 UNIQUEIDENTIFIER;
    DECLARE @test_mli6 VARCHAR(64) = 'TEST_MLI_006';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id6, 'Test Fish 6', 'Testus fishus6', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id6 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id6 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id6, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id6, @test_mli6, 'Test Lake 6', 1, 'Test Station 6', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@test_mli6, 4.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id6, @test_fish_id6, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    
    DECLARE @result_probability6 INT;
    SELECT @result_probability6 = today FROM dbo.fish_location WHERE station_Id = @test_station_id6 AND fish_Id = @test_fish_id6;
    
    IF @result_probability6 = 0 PRINT 'PASSED Test6 [sp_upsert_fish_oxygen_probability] Oxygen outside viable range (0% coefficient)';
    ELSE PRINT 'FAILED Test6 [sp_upsert_fish_oxygen_probability] Expected 0, got ' + CAST(ISNULL(@result_probability6, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test6 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------

-- Test 7: Oxygen at 90% zone
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @test_fish_id7 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_station_id7 UNIQUEIDENTIFIER = NEWID();
    DECLARE @test_rule_id7 UNIQUEIDENTIFIER;
    DECLARE @test_mli7 VARCHAR(64) = 'TEST_MLI_007';
    
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, stamp, numRuls, locked, fish_moon_sensitive, fish_migrate_pattern, fish_ability)
    VALUES (@test_fish_id7, 'Test Fish 7', 'Testus fishus7', (SELECT TOP 1 Family_id FROM dbo.fish_family), GETUTCDATE(), 0, 0, 0, 0, 0);
    SELECT @test_rule_id7 = id FROM dbo.fish_Rule WHERE fish_Id = @test_fish_id7 AND periodStart = -1 AND periodEnd = -1;
    INSERT INTO dbo.real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max, ri_stamp)
    VALUES (@test_rule_id7, 33, 6.0, 7.0, 8.0, 9.0, 10.0, GETUTCDATE());
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@test_station_id7, @test_mli7, 'Test Lake 7', 1, 'Test Station 7', 'Test Station Description', 'Test County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 999);
    INSERT INTO dbo.CurrentWaterState (mli, oxygen, stamp, iterstamp, sid)
    VALUES (@test_mli7, 7.0, GETUTCDATE(), GETUTCDATE(), 999);
    INSERT INTO dbo.fish_location (station_Id, fish_Id, probability, today, stamp)
    VALUES (@test_station_id7, @test_fish_id7, 100, 100, GETUTCDATE());
    
    EXEC dbo.sp_upsert_fish_oxygen_probability;
    
    DECLARE @result_probability7 INT;
    SELECT @result_probability7 = today FROM dbo.fish_location WHERE station_Id = @test_station_id7 AND fish_Id = @test_fish_id7;
    
    IF @result_probability7 = 90 PRINT 'PASSED Test7 [sp_upsert_fish_oxygen_probability] Oxygen at 90% zone';
    ELSE PRINT 'FAILED Test7 [sp_upsert_fish_oxygen_probability] Expected 90, got ' + CAST(ISNULL(@result_probability7, -999) AS VARCHAR(10));
    
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH ROLLBACK TRANSACTION; PRINT 'FAILED Test7 Error: ' + ERROR_MESSAGE(); END CATCH;
GO
-------------------------------------------------------------------------------------------------------------------------
