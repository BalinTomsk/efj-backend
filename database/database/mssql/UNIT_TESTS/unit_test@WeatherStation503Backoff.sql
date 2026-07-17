SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for weather-station-pusher HTTP 503 backoff procedures.
  Backoff state is stored on dbo.ows_meteo.backoffstate and TR_ows_meteo mirrors that state
  into dbo.WaterStation.supported.
*/
SET NOCOUNT ON;

BEGIN TRAN TestWeatherStation503Backoff
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @stationId uniqueidentifier;
DECLARE @stationId2 uniqueidentifier;
DECLARE @stationId3 uniqueidentifier;
DECLARE @mliKs varchar(64);
DECLARE @mliWa varchar(64);
DECLARE @mliWa2 varchar(64);
DECLARE @backoffstate int;
DECLARE @daily int;
DECLARE @weekly int;
DECLARE @next date;
DECLARE @supported bit;
DECLARE @count bigint;

BEGIN TRY
    SET @stationId = NEWID();
    SET @mliKs = 'UT503K' + RIGHT(REPLACE(CONVERT(varchar(36), @stationId), '-', ''), 12);
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@stationId, @mliKs, 'Unit Lake', 1, 'Unit Station KS', 'Unit Station', 'Unit', 1.0, 2.0, 'US', 'KS', 'UNIT', GETUTCDATE(), 1, 50301);
    IF EXISTS (SELECT 1 FROM dbo.ows_meteo WHERE mli = @mliKs)
        UPDATE dbo.ows_meteo
           SET WaterStation_id = @stationId, country = 'US', state = 'KS', lat = 1.0, lon = 2.0, stamp = '2026-06-30',
               backoffstate = 0, backoff_daily_503_count = 0, backoff_weekly_503_count = 0,
               backoff_last_503_date = NULL, backoff_next_date = NULL
         WHERE mli = @mliKs;
    ELSE
        INSERT INTO dbo.ows_meteo (WaterStation_id, mli, country, state, lat, lon, stamp)
        VALUES (@stationId, @mliKs, 'US', 'KS', 1.0, 2.0, '2026-06-30');

    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliKs, 'KS', '2026-07-01';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliKs, 'KS', '2026-07-02';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliKs, 'KS', '2026-07-03';
    SELECT @backoffstate = backoffstate, @daily = backoff_daily_503_count, @weekly = backoff_weekly_503_count,
           @next = backoff_next_date
      FROM dbo.ows_meteo
     WHERE mli = @mliKs;
    SELECT @supported = supported FROM dbo.WaterStation WHERE mli = @mliKs;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @backoffstate = 2 AND @daily = 3 AND @weekly = 0 AND @next = '2026-07-10' AND @supported = 0
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: three daily 503 failures set ows_meteo weekly backoff and unsupported station';
    ELSE
        RAISERROR ('TEST 1 FAIL [%dms]: expected backoffstate=2 daily=3 weekly=0 next=2026-07-10 supported=0', 16, -1, @ElapsedMs);

    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_weather_station_503_refresh_due '2026-07-10';
    SELECT @backoffstate = backoffstate, @next = backoff_next_date FROM dbo.ows_meteo WHERE mli = @mliKs;
    SELECT @supported = supported FROM dbo.WaterStation WHERE mli = @mliKs;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @backoffstate = 0 AND @next IS NULL AND @supported = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: due weekly backoff refresh restores supported station';
    ELSE
        RAISERROR ('TEST 2 FAIL [%dms]: refresh due must reset backoffstate and supported', 16, -1, @ElapsedMs);

    SET @stationId2 = NEWID();
    SET @mliWa = 'UT503W' + RIGHT(REPLACE(CONVERT(varchar(36), @stationId2), '-', ''), 12);
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@stationId2, @mliWa, 'Unit Lake', 1, 'Unit Station WA', 'Unit Station', 'Unit', 1.0, 2.0, 'US', 'WA', 'UNIT', GETUTCDATE(), 1, 50302);
    IF EXISTS (SELECT 1 FROM dbo.ows_meteo WHERE mli = @mliWa)
        UPDATE dbo.ows_meteo
           SET WaterStation_id = @stationId2, country = 'US', state = 'WA', lat = 1.0, lon = 2.0, stamp = '2026-06-30',
               backoffstate = 0, backoff_daily_503_count = 0, backoff_weekly_503_count = 0,
               backoff_last_503_date = NULL, backoff_next_date = NULL
         WHERE mli = @mliWa;
    ELSE
        INSERT INTO dbo.ows_meteo (WaterStation_id, mli, country, state, lat, lon, stamp)
        VALUES (@stationId2, @mliWa, 'US', 'WA', 1.0, 2.0, '2026-06-30');

    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-01';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-02';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-03';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-10';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-17';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-24';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa, 'WA', '2026-07-31';
    SELECT @backoffstate = backoffstate, @weekly = backoff_weekly_503_count, @next = backoff_next_date
      FROM dbo.ows_meteo
     WHERE mli = @mliWa;
    SELECT @supported = supported FROM dbo.WaterStation WHERE mli = @mliWa;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @backoffstate = 3 AND @weekly = 4 AND @next = '2026-08-31' AND @supported = 0
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: four weekly 503 failures set monthly backoff and unsupported station';
    ELSE
        RAISERROR ('TEST 3 FAIL [%dms]: expected backoffstate=3 weekly=4 next=2026-08-31 supported=0', 16, -1, @ElapsedMs);

    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_weather_station_503_reset 'unit-weather', 'US', @mliWa;
    SELECT @backoffstate = backoffstate, @daily = backoff_daily_503_count, @weekly = backoff_weekly_503_count,
           @next = backoff_next_date
      FROM dbo.ows_meteo
     WHERE mli = @mliWa;
    SELECT @supported = supported FROM dbo.WaterStation WHERE mli = @mliWa;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @backoffstate = 0 AND @daily = 0 AND @weekly = 0 AND @next IS NULL AND @supported = 1
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: successful processing reset restores supported station';
    ELSE
        RAISERROR ('TEST 4 FAIL [%dms]: reset must clear backoff and restore supported', 16, -1, @ElapsedMs);

    SET @stationId3 = NEWID();
    SET @mliWa2 = 'UT503X' + RIGHT(REPLACE(CONVERT(varchar(36), @stationId3), '-', ''), 12);
    INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid)
    VALUES (@stationId3, @mliWa2, 'Unit Lake', 1, 'Unit Station WA2', 'Unit Station', 'Unit', 1.0, 2.0, 'US', 'WA', 'UNIT', GETUTCDATE(), 1, 50303);
    IF EXISTS (SELECT 1 FROM dbo.ows_meteo WHERE mli = @mliWa2)
        UPDATE dbo.ows_meteo
           SET WaterStation_id = @stationId3, country = 'US', state = 'WA', lat = 1.0, lon = 2.0, stamp = '2026-06-30',
               backoffstate = 0, backoff_daily_503_count = 0, backoff_weekly_503_count = 0,
               backoff_last_503_date = NULL, backoff_next_date = NULL
         WHERE mli = @mliWa2;
    ELSE
        INSERT INTO dbo.ows_meteo (WaterStation_id, mli, country, state, lat, lon, stamp)
        VALUES (@stationId3, @mliWa2, 'US', 'WA', 1.0, 2.0, '2026-06-30');
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa2, 'WA', '2026-07-01';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa2, 'WA', '2026-07-02';
    EXEC dbo.sp_weather_station_503_record 'unit-weather', 'US', @mliWa2, 'WA', '2026-07-03';

    SET @tStart = SYSUTCDATETIME();
    DECLARE @summary TABLE (state char(2), backoff_stage varchar(16), station_count bigint);
    INSERT INTO @summary EXEC dbo.sp_weather_station_503_summary_by_state;
    SELECT @count = station_count FROM @summary WHERE state = 'WA' AND backoff_stage = 'WEEKLY';
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @count = 1
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: summary reduces ows_meteo 503 backoff stations by state';
    ELSE
        RAISERROR ('TEST 5 FAIL [%dms]: expected WA weekly count 1', 16, -1, @ElapsedMs);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
ROLLBACK TRAN TestWeatherStation503Backoff
GO
