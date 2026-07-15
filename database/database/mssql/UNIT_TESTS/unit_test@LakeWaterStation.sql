SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_lake_water_stations (monitoring-station 'X' markers on the
  river-viewer map; caller: FishTracker Resources/wfRiverViewer.aspx.cs GetWaterStationPoints).
  Uses real table dbo.WaterStation (lakeId has no FK, so no parent setup needed).
  Transaction is rolled back at end - database state fully restored.

  TEST 1 - Two stations on one water body -> both returned with mli/lat/lon/locName
  TEST 2 - A station of ANOTHER water body is not returned; unknown lake -> zero rows
*/
SET NOCOUNT ON;

DECLARE @LakeA     uniqueidentifier = NEWID();
DECLARE @LakeB     uniqueidentifier = NEWID();
DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- WaterStation.lakeId has FK_WaterStation_Lake -> parent lakes first
    INSERT INTO dbo.Lake (Lake_id, locType, lake_name)
    VALUES (@LakeA, 2, N'UT Lake A'),
           (@LakeB, 2, N'UT Lake B');

    INSERT INTO dbo.WaterStation (MLI, lat, lon, country, locDesc, locType, locName, county, sid, lakeId, lakeName, supported)
    VALUES (N'UT_MLI_A1', 45.10, -75.10, 'CA', N'unit-test station A1', 2, N'UT Station A1', N'', 990001, @LakeA, N'UT Lake A', 1),
           (N'UT_MLI_A2', 45.20, -75.20, 'CA', N'unit-test station A2', 2, N'UT Station A2', N'', 990002, @LakeA, N'UT Lake A', 1),
           (N'UT_MLI_B1', 46.00, -76.00, 'CA', N'unit-test station B1', 2, N'UT Station B1', N'', 990003, @LakeB, N'UT Lake B', 1);

    -- ----------------------------------------------------------------
    -- TEST 1: both stations of @LakeA come back, fields intact
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @CntA int, @CntA1 int;
    SELECT @CntA = COUNT(*) FROM dbo.fn_lake_water_stations(@LakeA);
    SELECT @CntA1 = COUNT(*) FROM dbo.fn_lake_water_stations(@LakeA)
    WHERE mli = N'UT_MLI_A1' AND sid = 990001 AND locName = N'UT Station A1'
      AND lat = 45.10 AND lon = -75.10;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @CntA = 2 AND @CntA1 = 1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two stations returned for the water body with correct fields';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2 rows (A1 matching), got ' + CAST(@CntA AS varchar) + '/' + CAST(@CntA1 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: no cross-lake leakage; unknown lake -> zero rows
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Leak int, @CntNone int;
    SELECT @Leak = COUNT(*) FROM dbo.fn_lake_water_stations(@LakeA) WHERE mli = N'UT_MLI_B1';
    SELECT @CntNone = COUNT(*) FROM dbo.fn_lake_water_stations(NEWID());
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Leak = 0 AND @CntNone = 0
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: other-lake station excluded, unknown lake returns no rows';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: leak=' + CAST(@Leak AS varchar) + ', unknown-lake rows=' + CAST(@CntNone AS varchar);

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , N'unit_test@LakeWaterStation' AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
