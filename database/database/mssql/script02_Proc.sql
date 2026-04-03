-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spSaveUser' AND type = 'P')
    DROP PROCEDURE dbo.spSaveUser
GO
/*
    Register new User Account
*/
create PROCEDURE dbo.spSaveUser @ipaddr varchar(32), @agent varchar(128)
    , @addr varchar(32), @host varchar(255), @user varchar(255), @email varchar(255), @country char(2)
    , @postal varchar(16), @fname nvarchar(64), @lname nvarchar(64), @psw varchar(128)
AS
SET NOCOUNT ON
BEGIN TRY  
    INSERT INTO Users (userName, email, ipaddr, agent, addr, host, country, postal, firstName, lastName, psw, question, answer) 
        VALUES (@user, @email, @ipaddr, @agent, @addr, @host, @country, @postal, @fname, @lname, HashBytes('MD5', @psw + '*solt'), 'dog', 0x0024);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO

/*
DECLARE @userId uniqueidentifier

EXEC dbo.spAddUser 'guest',   'password',   'Mr.', 'John', 'Doe', 'tn@mail.ru',            'N2M5L3', 1, 'kon',  'palto', 15198045308, @userId OUT
EXEC dbo.spAddUser 'BassPro', 'Toronto123', 'Mr.', 'John', 'Doe', 'LBarmalgeen@gmail.com', 'N2M5L5', 1, 'Bass', 'Pro',   15198045308, @userId OUT
UPDATE Users SET access = 3 WHERE id= @userId    -- 3- reseller, 255 - superadmin, 1 - normal user, 2 - typewriter
SELECT @userId
GO
*/
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spTestUser' AND type = 'P')
    DROP PROCEDURE dbo.spTestUser
GO

CREATE PROCEDURE spTestUser @userName  varchar(64), @psw varchar(128), @userId uniqueidentifier OUT
AS
SET NOCOUNT ON
BEGIN TRY
  SELECT @userId = ID FROM Users WHERE HashBytes('MD5', @psw + '*solt')= psw AND RTRIM(@userName) = userName
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spSaveSession' AND type = 'P')
    DROP PROCEDURE dbo.spSaveSession
GO

CREATE PROCEDURE dbo.spSaveSession @ipaddr varchar(32), @agent varchar(128)
    , @host varchar(32), @page varchar(MAX), @cookie varchar(64), @sessionId uniqueidentifier OUT
AS
SET NOCOUNT ON
BEGIN TRY
    IF @page LIKE '%PushStation.aspx'
        RETURN
  SET @sessionId = NULL
  DECLARE @tmp TABLE( id uniqueidentifier )
  IF @page NOT IN ('/Default.aspx', '/Resources/wfRiverViewer.aspx')
	  INSERT INTO SessionHandler(  ipAddr,  userAgent,  host,  startPage ) 
		OUTPUT INSERTED.ID INTO @tmp( id ) VALUES ( @ipaddr, @agent, @host, @page )
  IF EXISTS (SELECT * FROM @tmp ) 
    SELECT TOP 1 @sessionId = id FROM @tmp
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO

-------------------------------------- -------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spSaveWeatherState' AND type = 'P')
    DROP PROCEDURE dbo.spSaveWeatherState
GO

CREATE PROCEDURE spSaveWeatherState @condition varchar(255), @placeId int, @mli varchar(64) OUT
WITH EXEC AS CALLER
AS
BEGIN TRY
SET NOCOUNT ON
  SELECT @mli = mli FROM WaterStation WHERE  sid = @placeId
  UPDATE WaterStation SET condition=@condition, wheatherStamp = GETUTCDATE() WHERE sid = @placeId
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO

--------------------------------  direct push--------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spUpdateCurrentWaterState' AND type = 'P')
    DROP PROCEDURE dbo.spUpdateCurrentWaterState
GO

-- EXEC spPushSpeciesFromLakeToStation
CREATE PROCEDURE spUpdateCurrentWaterState @mli varchar(64), @stamp datetime, @elevation float, @sid bigint 
   , @temperature float, @conductance float, @ph float 
   , @turbidity float,   @oxygen float,      @discharge float
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON
  IF @mli IS NOT NULL
  BEGIN
    INSERT INTO dbo.WaterData (mli, stamp, temperature, discharge, turbidity, oxygen, ph, elevation)
      VALUES (@mli, @stamp, @temperature, @discharge, @turbidity, @oxygen, CAST(@ph as float) * 10.0, @elevation)
    RETURN @@ROWCOUNT      
  END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------

--  EXEC spStepPushSpeciesFromLakeToStation
-----------------------------------  related push--------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spStepPushSpeciesFromLakeToStation' AND type = 'P')
    DROP PROCEDURE dbo.spStepPushSpeciesFromLakeToStation
GO

CREATE PROCEDURE spStepPushSpeciesFromLakeToStation
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON;
  DECLARE @return_value int = -1
    -- push fishes from lakes to station place with the same type
  INSERT dbo.fish_location (station_Id, fish_Id, today ) 
    SELECT id, fish_Id, (CASE WHEN today > 100 THEN 100 ELSE today END ) AS today FROM
    (
        select id, fish_Id, ( MAX((50 * spawnPeriod) + probability * ( today / 100)) ) AS today FROM
        (
            select id, fish_Id, today, spawnPeriod
                 , (CASE WHEN probability > 0.1 THEN ( probability - correction / way_correction ) ELSE probability END) AS probability FROM
            ( 
                select w.id, lf.fish_Id, probability, spawnPeriod,
                    (CASE probability_source_type WHEN 0 then 100 when 1 then 90 when 2 then 75 when 4 then 50 else 0 end) as today,
                    (CASE WHEN tributaries = 1 THEN 0 ELSE 0.1 END) AS correction,            -- probability correction
                    (CASE WHEN m.lake_id = lf.lake_Id THEN 1 ELSE 2 END) AS way_correction      -- outflow increase probability
                    FROM dbo.lake_fish lf
                    left join Tributaries m ON lf.lake_id = m.main_lake_id
                    left join Tributaries s ON lf.lake_id = s.main_lake_id
                    join lake l ON (m.lake_id = lf.lake_Id or s.lake_id = lf.lake_Id)
                    join 
                     (
                        SELECT fish_id, habitat, spawnPeriod, periodStart, periodEnd FROM 
                        (
                          SELECT fish_id, habitat, 0 AS spawnPeriod, periodStart, periodEnd 
                            FROM fish_rule WHERE -1 = periodStart AND -1 = periodEnd
                          UNION ALL
                          SELECT fish_id, habitat, 1 AS spawnPeriod, periodStart, periodEnd 
                            FROM fish_rule WHERE -1 <> periodStart AND -1 <> periodEnd
                        )e WHERE spawnPeriod = (CASE WHEN DATEPART( MM, getdate()) BETWEEN periodStart AND periodEnd THEN 1 ELSE 0 END)
                      )d
                        ON ( d.fish_id = lf.fish_id AND d.habitat = ( l.locType & d.habitat ) )
                    join dbo.WaterStation w ON (w.lakeId  = l.lake_id )

            )c
        )b  group by  id, fish_Id
    ) a
    WHERE NOT EXISTS (SELECT * FROM fish_location fl WHERE fl.station_Id = a.id AND fl.fish_Id = a.fish_Id)

    SET @return_value = @@ROWCOUNT;
    RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spGetPlaceByFish' AND xtype = 'P')
    DROP PROCEDURE dbo.spGetPlaceByFish
GO
-- SELECT sid, name, county, state, lat, lon, today FROM dbo.GetLocations( 'Burbot', 42, -80, 1 )
-- SELECT [name], county, state, lat, lon, today FROM dbo.GetLocations( 'Lake Chub', 42, -80, 1 )  ORDER BY state ASC
create PROCEDURE dbo.spGetPlaceByFish @fishName  varchar(64), @lat float, @lon float, @dist float
AS 
SET NOCOUNT ON
BEGIN TRY
  DECLARE @fishId uniqueidentifier
  DECLARE @tbl TABLE(  mli varchar(64) PRIMARY KEY, county varchar(64), state char(2), country char(2)
                     , location varchar(max), sid int, lat float, lon float, today int, lakeId uniqueidentifier)
  SELECT @fishId = fish_ID FROM dbo.fish WHERE fish_name like @fishName
  INSERT INTO @tbl 
    SELECT  w.mli, w.county, w.state, w.country, w.LocName, w.sid, w.lat, w.lon, f.today , w.lakeId
     FROM dbo.vWaterStation w 
       JOIN dbo.fish_location f ON ( f.station_Id = w.id )
       JOIN dbo.fish       s ON ( f.fish_Id    = s.fish_Id )
      WHERE ( w.lat between (@lat-@dist) AND (@lat+@dist) ) AND (w.lon between (@lon-@dist) AND (@lon+@dist) ) 
           AND s.fish_name like @fishName  
   -- delete  fishes ae not belong to watershield
   DELETE FROM @tbl WHERE country = 'CA' AND state = 'ON' 
      AND mli NOT IN (SELECT w.mli FROM dbo.WaterStation w, Lake_fish l  
       WHERE w.lakeId=l.lake_Id AND l.fish_Id = @fishId AND w.country = 'CA' AND w.state = 'ON')
   SELECT * FROM @tbl
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
-- exec spGetPlaceByFish 'Burbot', 41, -82, 3
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spTotalUpdateProbability' AND xtype = 'P')
    DROP PROCEDURE dbo.spTotalUpdateProbability
GO

-- EXEC spTotalUpdateProbability
create PROCEDURE dbo.spTotalUpdateProbability
WITH EXEC AS CALLER
AS
BEGIN TRY    -- procedure called every hour by external caller
  SET NOCOUNT ON
   DECLARE @return_value int = -1
   BEGIN TRAN T1a;
    ;WITH cte (today, station_Id, fish_Id) AS 
    (
      SELECT ( probability + ( 33 * tm.koef ) ), t.station_Id, t.fish_Id
            FROM [dbo].[fish_location] t WITH (NOLOCK)
            JOIN [dbo].[WaterStation]  s WITH (NOLOCK) ON ( t.station_Id = s.id )  
            JOIN [dbo].[fn_get_koef_fish_station_temperature] tm ON (tm.fish_Id = t.fish_Id AND tm.mli = s.mli)
            JOIN [dbo].WaterData       d WITH (NOLOCK) ON ( d.mli = s.mli )  
      WHERE d.temperature Is NOT NULL
    ) 
    -- probability cannot be bigger the 100%
    UPDATE t SET t.stamp = getutcdate(), t.today = (CASE WHEN cte.today > 100 THEN 100 ELSE cte.today END)
        FROM cte JOIN fish_location t  WITH (NOLOCK) ON ( t.station_Id = cte.station_Id AND t.fish_Id = cte.fish_Id )
        WHERE cte.today > 100;
    SET @return_value = @@ROWCOUNT;
   COMMIT TRAN T1a;

   BEGIN TRAN T1b;
    ;WITH cte (today, station_Id, fish_Id) AS 
    (
      SELECT ( probability + ( 33 * tm.koef ) ), t.station_Id, t.fish_Id
            FROM [dbo].[fish_location] t WITH (NOLOCK)
            JOIN [dbo].[WaterStation]  s WITH (NOLOCK) ON ( t.station_Id = s.id )  
            JOIN [dbo].[fn_get_koef_fish_station_oxygen] tm ON (tm.fish_Id = t.fish_Id AND tm.mli = s.mli)
            JOIN [dbo].WaterData       d WITH (NOLOCK) ON ( d.mli = s.mli )  
      WHERE d.oxygen Is NOT NULL
    ) 
    -- probability cannot be bigger the 100%
    UPDATE t SET t.stamp = getutcdate(), t.today = (CASE WHEN cte.today > 100 THEN 100 ELSE cte.today END)
        FROM cte JOIN fish_location t  WITH (NOLOCK) ON ( t.station_Id = cte.station_Id AND t.fish_Id = cte.fish_Id )
        WHERE cte.today > 100;
    SET @return_value = @return_value + @@ROWCOUNT;
   COMMIT TRAN T1b;

   BEGIN TRAN T1c;
    ;WITH cte (today, station_Id, fish_Id) AS 
    (
      SELECT ( probability + ( 25 * tm.koef ) ), t.station_Id, t.fish_Id
            FROM [dbo].[fish_location] t WITH (NOLOCK)
            JOIN [dbo].[WaterStation]  s WITH (NOLOCK) ON ( t.station_Id = s.id )  
            JOIN [dbo].[fn_get_koef_fish_station_ph] tm ON (tm.fish_Id = t.fish_Id AND tm.mli = s.mli)
            JOIN [dbo].WaterData       d WITH (NOLOCK) ON ( d.mli = s.mli )  
      WHERE d.ph Is NOT NULL
    ) 
    -- probability cannot be bigger the 100%
    UPDATE t SET t.stamp = getutcdate(), t.today = (CASE WHEN cte.today > 100 THEN 100 ELSE cte.today END)
        FROM cte JOIN fish_location t  WITH (NOLOCK) ON ( t.station_Id = cte.station_Id AND t.fish_Id = cte.fish_Id )
        WHERE cte.today > 100;
    SET @return_value = @return_value + @@ROWCOUNT;
   COMMIT TRAN T1c;

   /*
   BEGIN TRAN T2b;
        -- cast date and leave only one value per hour
        update WaterData set stamp = DATEADD(HOUR, datepart(HOUR, stamp), cast(cast(stamp as date)as datetime)) 
            WHERE stamp between DATEADD( DAY, -2, getutcdate()) AND DATEADD( DAY, -1, getutcdate()) AND datepart(mi, stamp) BETWEEN 1 and 29 
        update WaterData set stamp = DATEADD(HOUR, 1+datepart(HOUR, stamp), cast(cast(stamp as date)as datetime)) 
            WHERE stamp between DATEADD( DAY, -2, getutcdate()) AND DATEADD( DAY, -1, getutcdate()) AND datepart(mi, stamp) BETWEEN 30 and 59 
   COMMIT TRAN T2b;

   BEGIN TRAN T2c;
            DECLARE @t TABLE(id int not null primary key)
            INSERT INTO @t select max(id) from WaterData where stamp between DATEADD( DAY, -2, getutcdate()) AND DATEADD( DAY, -1, getutcdate()) and datepart(mi, stamp) = 0 group by mli  

        delete from WaterData where stamp between DATEADD( DAY, -2, getutcdate()) AND DATEADD( DAY, -1, getutcdate()) and datepart(mi, stamp) = 0
            and id not in ( select id from @t )
    COMMIT TRAN T2c;
    */

   -------------------------------------------------------------------------------------------------------------
   BEGIN TRAN T3;
        DECLARE @dt DATE = DATEADD( DAY, -21, getutcdate() );
        DELETE FROM WaterData WHERE stamp < @dt
   COMMIT TRAN T3;

   BEGIN TRAN T4;
        DECLARE @dt2 DATE = DATEADD( DAY, -21, getutcdate() );
        DELETE FROM Weather_Forecast WHERE dt < @dt2
   COMMIT TRAN T4;


   RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO               
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_weather_save_city' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_weather_save_city
GO

CREATE PROCEDURE dbo.sp_weather_save_city @city_id int, @city_name nvarchar(32), @lat float, @lon float
                                        , @country char(2), @population int, @mli varchar(64)
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON;
  DECLARE @return_value int = -1

    IF NOT EXISTS (SELECT * FROM city WHERE @city_name = place 
       AND @country = country  AND ( ABS(lat) BETWEEN ( ABS(CAST(@lat AS INT))-1 ) AND ( ABS(CAST(@lat AS INT))+1 ) ) 
                               AND ( ABS(lon) BETWEEN ( ABS(CAST(@lon AS INT))-1 ) AND ( ABS(CAST(@lon AS INT))+1 ) ) )
    BEGIN
        INSERT INTO city ( place,  state, lat, lon, country, region, city_id, population, stamp )
                VALUES ( @city_name, '  ', @lat, @lon, @country, -1, @city_id, @population, getutcdate()  )
    END ELSE
        IF EXISTS (SELECT * FROM city WHERE @city_name = place 
           AND @country = country  AND ( ABS(lat) BETWEEN ( ABS(CAST(@lat AS INT))-1 ) AND ( ABS(CAST(@lat AS INT))+1 ) ) 
                                   AND ( ABS(lon) BETWEEN ( ABS(CAST(@lon AS INT))-1 ) AND ( ABS(CAST(@lon AS INT))+1 ) ) )
        BEGIN
          UPDATE city SET city_id = @city_id WHERE @city_name = place AND @country = country
            AND ( ABS(lat) BETWEEN ( ABS(CAST(@lat AS INT))-1 ) AND ( ABS(CAST(@lat AS INT))+1 ) ) 
            AND ( ABS(lon) BETWEEN ( ABS(CAST(@lon AS INT))-1 ) AND ( ABS(CAST(@lon AS INT))+1 ) ) 
        END
    UPDATE WaterStation SET city_id = @city_id WHERE mli = @mli
    RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spGetPlaceByFish_stale' AND xtype = 'P')
    DROP PROCEDURE dbo.spGetPlaceByFish_stale
GO

create PROCEDURE spGetPlaceByFish_stale @fishName  varchar(64), @lat float, @lon float, @dist float
AS     -- exec [dbo].[spGetPlaceByFish] 'burbot', 43, -81, 3
SET NOCOUNT ON    --lat, lon, today, location, sid, country, state, county
  DECLARE @fishId uniqueidentifier = (SELECT TOP 1 fish_id FROM fish WHERE fish_name like @fishName )
  DECLARE @tbl TABLE(  lat float, lon float, today int, location varchar(max), sid int
                     , country char(2), state char(2), county varchar(64))
  INSERT INTO @tbl 
   SELECT lat,  lon , today, LocName, sid, country, state, county FROM
   (
        SELECT  w.lat, w.lon, f.today, w.LocName, w.sid, w.country, w.state, w.county 
         FROM dbo.vWaterStation w 
           JOIN dbo.fish_location f ON ( f.station_Id = w.id )
           JOIN dbo.fish          s ON ( f.fish_Id    = s.fish_Id )
          WHERE  
 --           ( w.lat between (@lat-@dist) AND (@lat+@dist) ) AND (w.lon between (@lon-@dist) AND (@lon+@dist) ) AND 
               s.fish_id = @fishId
   )a
   SELECT lat, lon, today, location, sid, country, state, county FROM @tbl
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_tributary' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_tributary
GO

-- 1 - left, 2- right, 4 - inflows, 8 - outflows, 16 - source, 32 - mouth
CREATE PROCEDURE sp_add_tributary @Main_Lake_id uniqueidentifier, @Lake_id uniqueidentifier, @side int, @flow int, @lat float, @lon float, @level int
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON

    IF EXISTS (SELECT * FROM lake WHERE lake_id = @Lake_id AND locType in (1, 8, 8192))
    BEGIN
        INSERT INTO Tributaries (Main_Lake_id, Lake_id, side, lat, lon, elevation) values (@Lake_id, @Main_Lake_id, @side, @lat, @lon, @level);
    END
    ELSE
    BEGIN
        update  Tributaries SET Lake_id = @Main_Lake_id, lat = COALESCE(@lat, lat), lon = COALESCE(@lon, lon) , elevation = COALESCE(@level, elevation)  
            WHERE Main_Lake_id = @Lake_id AND side = 32
    END
    IF @@ROWCOUNT > 0
        UPDATE lake SET stamp = getdate() WHERE lake_id IN (@Main_Lake_id, @Lake_id)
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;        
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spSaveException' AND xtype = 'P')
    DROP PROCEDURE dbo.spSaveException
GO

create PROCEDURE spSaveException @ip varchar(64), @msg nvarchar(1024), @page_name sysname, @email sysname
AS
SET NOCOUNT ON
BEGIN TRY  
  INSERT INTO LogException( ip, msg, page_name, email ) values (@ip, @msg, @page_name, @email);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;          
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_zone_regulation' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_zone_regulation
GO

-- add regulation to zone
-- http://files.ontario.ca/environment-and-energy/fishing/mnr_e001331.pdf
--- EXEC sp_add_zone_regulation 2, '2CFFB500-3E59-4120-9460-055856E9AC5C', '20150415', 'Friday before the 3rd Saturday in May'
--               , '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', 8, ''
create PROCEDURE dbo.sp_add_zone_regulation @zone_id int, @fish_id uniqueidentifier, @date_start varchar(64), @date_end varchar(64)
               , @sport nvarchar(255), @reacr nvarchar(255), @code int, @link nvarchar(255)
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    declare @start date,  @end date;
    declare @sstart varchar(64), @send varchar(64);
    BEGIN TRY  
        SET @start = @date_start
    END TRY
    BEGIN CATCH
        SET @sstart = @date_start
    END CATCH;          
    -- end date
    BEGIN TRY  
        SET @end = @date_end
    END TRY
    BEGIN CATCH
        SET @send = @date_end
    END CATCH;          

    IF @start IS NOT NULL AND @end IS NOT NULL 
    BEGIN
        insert into zone_regulations (zone_id, fish_id, regulations_date_start, regulations_date_end, regulations_sport_text, regulations_consr_text, regulations_code, regulations_link) 
                values      ( @zone_id, @fish_id, @start, @end, @sport, @reacr, @code, @link);
    END
    ELSE IF @start IS NOT NULL AND @end IS NULL 
    BEGIN
        insert into zone_regulations (zone_id, fish_id, regulations_date_start, regulations_end, regulations_sport_text, regulations_consr_text, regulations_code, regulations_link) 
                values      ( @zone_id, @fish_id, @start, @send, @sport, @reacr, @code, @link);
    END
    ELSE IF @start IS NULL AND @end IS NOT NULL 
    BEGIN
        insert into zone_regulations (zone_id, fish_id, regulations_start, regulations_date_end, regulations_sport_text, regulations_consr_text, regulations_code, regulations_link) 
                values      ( @zone_id, @fish_id, @sstart, @end, @sport, @reacr, @code, @link);
    END
    ELSE IF @start IS NULL AND @end IS NULL 
    BEGIN
        insert into zone_regulations (zone_id, fish_id, regulations_start, regulations_end, regulations_sport_text, regulations_consr_text, regulations_code, regulations_link) 
                values      ( @zone_id, @fish_id, @sstart, @send, @sport, @reacr, @code, @link);
    END
    SELECT * FROM vw_zone_regulation
        WHERE zone_id = @zone_id ORDER BY regulations_stamp DESC;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_fish_river' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_fish_river
GO

/******
 *  add the fish to the river or update existing with ner fact
 *  @fish_id     uniqueidentifier        - fish identifyer
 *  @lake_id     uniqueidentifier        - lake identifyer
 *  @link        nvarchar(512)          - http link to the source
 *  @created     datetime2              - date when information was entered
 *  @probability int                    - 0 - science documents (high priority), 1- site owner, 2 - paid fishers, 3 - unknown fishers
 *  @note        nvarchar(1024)         - note about fishing
 *
 *  Usage: exec sp_add_fish_river 'F124F917-D11F-4ED9-9B59-863D184CBFED', '1864853F-F9B7-41E7-A66C-3359961AB6A4', 'http://files.ontario.ca/environment-and-energy/fishing/mnr_e001331.pdf', '2014', 0
 *
 */
create PROCEDURE sp_add_fish_river @fish_id uniqueidentifier, @lake_id uniqueidentifier, @link nvarchar(512)
              , @created datetime2 = NULL, @probability int = 0, @note nvarchar(1024)  = null
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    IF @created Is NULL SET @created = '19000101'

    declare @init_prb int = CASE
        WHEN @probability IN (0,1) THEN 100
        WHEN @probability = 2 THEN 90
        WHEN @probability = 3 THEN 75 ELSE 50 END;

    declare @fish uniqueidentifier = ( select fish_id from fish where fish_id = @fish_id );
    declare @lake uniqueidentifier = ( select lake_id from lake where lake_id = @lake_id );

    if ( @fish IS NULL AND @lake IS NULL ) 
    BEGIN
        SET @fish = @lake_id;
        SET @lake = @fish_id;
    END ELSE
    BEGIN
      IF @fish IS NULL
        SET @fish = ( select fish_id from fish where fish_name = @fish_id );
      IF @lake IS NULL
        SET @lake = ( select lake_id from lake where lake_name = @lake_id );
    END
    SET @fish = ( select fish_id from fish where fish_id = @fish_id );
    SET @lake = ( select lake_id from lake where lake_id = @lake_id );

    if ( @fish IS NULL AND @lake IS NULL ) 
    BEGIN
        SET @fish = @lake_id;
        SET @lake = @fish_id;
    END

    IF NOT EXISTS (SELECT link FROM lake_fish WHERE @fish_id = fish_id AND @lake_id = lake_id AND probability_source_type = @probability)
    BEGIN
    INSERT INTO lake_fish (  lake_id,  fish_id, link,   created, probability, probability_source_type, note )
        VALUES            ( @lake_id, @fish_id, @link, @created, @init_prb,   @probability, @note);
    END
    ELSE
    BEGIN
        UPDATE lake_fish SET link = COALESCE(@link, link), note = COALESCE(@note, note), created = getdate()
            WHERE  lake_id = @lake_id AND fish_id = @fish_id AND probability_source_type > @probability;
    END

    SELECT l.lake_name, f.fish_name, l.lake_id, f.fish_id FROM lake l 
        JOIN lake_fish lf ON l.lake_id = lf.lake_Id 
        JOIN fish       f ON f.fish_id = lf.fish_Id 
        WHERE l.lake_id = @lake_id ORDER BY lf.created DESC
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
---------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_regulation' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_regulation
GO

-- add regulation to river/lake
-- http://files.ontario.ca/environment-and-energy/fishing/mnr_e001331.pdf
-- 1 - Fish sanctuary - no fishing
/*
    @zone_id        int                         -- regulation zone 1-17 in Ontario
    @part           nvarchar(255)               -- 'Kenny, Gladman, Flett, Gooderham and Milne Twps. '
    @date_start     varchar(64)                 -- date, could be day of week or special event
    @date_end       varchar(64)                 -- date, could be day of week or special event
    @sport          nvarchar(255)               -- number of fishes for sport license 
    @reacr          nvarchar(255)               -- number of fishes for recreational license license 
    @code           int                         -- code
    @fish_id        uniqueidentifier
    @lake_id        uniqueidentifier
    @link           nvarchar(255)               -- http link to document
    @enter_year     int                         -- year when regualation was published

    EXEC sp_add_regulation 'ON', 10, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
        , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019, 1

    EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e'
        , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 1

    EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', '5, not more than 1 greater than 40 cm', '2, not more than 1 greater than 40'
        , NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e', NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 1

-- select * from regulations
-- delete from regulations

*/

CREATE PROCEDURE dbo.sp_add_regulation @state char(2), @zone_id int, @part nvarchar(255), @date_start varchar(64), @date_end varchar(64)
        , @sport nvarchar(255), @reacr nvarchar(255), @code int
        , @fish_id uniqueidentifier, @lake_id uniqueidentifier, @link nvarchar(255), @enter_year int = NULL, @postview bit = 0
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    IF @enter_year IS NULL
    BEGIN
        SET @enter_year = DATEPART(YEAR, getdate());
    END
    IF @date_start IS NULL 
    BEGIN
        SET @date_start = CAST(DATEPART(YEAR, getdate()) AS varchar(4)) + '0101';
    END
    IF @date_end IS NULL 
    BEGIN
        SET @date_end = CAST(DATEPART(YEAR, getdate()) AS varchar(4)) + '1231';
    END;

    -- set zone to river
    IF @zone_id IS NOt NULL AND @lake_id IS NOT NULL
    BEGIN
        UPDATE Tributaries SET zone = @zone_id WHERE lake_id = @lake_id AND main_lake_id = @lake_id ANd side=32

        exec sp_add_fish_river @fish_id, @lake_id, @link, null, 0, '';
    END
    declare @start date = (SELECT TRY_PARSE(@date_start AS datetime USING 'en-US') );
    declare @end date = (SELECT TRY_PARSE(@date_end AS datetime USING 'en-US') );
    declare @regulations_start  varchar(64), @regulations_end varchar(64);

    declare @sportint int = TRY_CONVERT(int, @sport);
    declare @reacrint int = TRY_CONVERT(int, @reacr);

    IF @start IS NULL
        SET @regulations_start = @date_start;

    IF @end IS NULL
        SET @regulations_end = @date_end;

    declare @idstart int = (SELECT MAX(id) FROM regulations)

--    IF @start IS NOT NULL AND @end IS NOT NULL 
    BEGIN
        insert into regulations ( state, zone_id, fish_id, lake_id, regulations_start, regulations_date_start, regulations_end, regulations_date_end
                                , regulations_part, regulations_sport, regulations_sport_text, regulations_consr, regulations_consr_text, regulations_code, regulations_link) 
                    values      ( @state, @zone_id, @fish_id, @lake_id, @regulations_start, @start, @regulations_end, @end, @part, @sportint, @sport, @reacrint, @reacr, @code, @link);
    END
    If @postview = 1
        SELECT * FROM regulations WHERE @idstart < id OR @idstart IS NULL
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
---------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_MergeLakes' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_MergeLakes
GO

create PROCEDURE dbo.sp_MergeLakes @fromLake uniqueidentifier, @toLake uniqueidentifier
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    IF NOT EXISTS(SELECT * FROM lake where lake_id=@fromLake)
        RETURN

     update WaterStation set lakeid= @toLake where lakeid = @fromLake 
    BEGIN
        delete from lake_fish where lake_id = @toLake
            AND fish_id in (SELECT fish_id FROM lake_fish WHERE lake_id = @fromLake)
        update lake_fish set lake_id = @toLake where lake_id = @fromLake 
    END
    BEGIN
        delete from lake_state where lake_id = @toLake
            AND month in (SELECT month FROM lake_state WHERE lake_id = @fromLake)
        update lake_fish set lake_id = @toLake where lake_id = @fromLake 
    END    update spot set lake_id = @toLake where lake_id = @fromLake 
    update zone_regulations set lake_id = @toLake where lake_id = @fromLake 
    update lake SET source=@toLake where source=@fromLake
    update lake SET mouth=@toLake where mouth=@fromLake
    update news SET lake_id=@toLake where lake_id=@fromLake

    update t set t.phosphorus=COALESCE(s.phosphorus, t.phosphorus )
	           , t.PH=COALESCE(s.PH, t.PH )
	           , t.TDS=COALESCE(s.TDS, t.TDS )
	           , t.Conductivity=COALESCE(s.Conductivity, t.Conductivity )
	           , t.Alkalinity=COALESCE(s.Alkalinity, t.Alkalinity )
	           , t.Hardness=COALESCE(s.Hardness, t.Hardness )
	           , t.Sodium=COALESCE(s.Sodium, t.Sodium )
	           , t.Chloride=COALESCE(s.Chloride, t.Chloride )
	           , t.Bicarbonate=COALESCE(s.Bicarbonate, t.Bicarbonate )
	           , t.transparency=COALESCE(s.transparency, t.transparency )
	           , t.oxygen=COALESCE(s.oxygen, t.oxygen )
	           , t.Salinity=COALESCE(s.Salinity, t.Salinity )
	    FROM lake_state t, lake_state s WHERE t.lake_id = @toLake AND s.lake_id = @fromLake

    update t set t.link = s.link 
            , t.length=COALESCE(s.length, t.length )
            , t.depth=COALESCE(s.depth, t.depth )
            , t.width=COALESCE(s.width, t.width )

            , t.old_id=COALESCE(s.old_id, t.old_id )
            , t.basin=COALESCE(s.basin, t.basin )
            , t.descript=COALESCE(s.descript, t.descript )
            , t.IsFish=COALESCE(s.IsFish, t.IsFish )
            , t.regulations=COALESCE(s.regulations, t.regulations )
            , t.link_reg=COALESCE(s.link_reg, t.link_reg )
            , t.drainage=COALESCE(s.drainage, t.drainage )
            , t.Discharge=COALESCE(s.Discharge, t.Discharge )
            , t.watershield=COALESCE(s.watershield, t.watershield )
            , t.fishing=COALESCE(s.fishing, t.fishing )
            , t.Volume=COALESCE(s.Volume, t.Volume )
            , t.Shoreline=COALESCE(s.Shoreline, t.Shoreline )
            , t.surface=COALESCE(s.surface, t.surface )
            , t.isWell=COALESCE(s.isWell, t.isWell )
            , t.lake_road_access=COALESCE(s.lake_road_access, t.lake_road_access )
            , t.CGNDB = CASE WHEN t.CGNDB IS NULL THEN s.CGNDB ELSE t.CGNDB END
    FROM lake t, lake s WHERE t.lake_id = @toLake AND s.lake_id = @fromLake

    update t set
        t.location = COALESCE(f.location, t.location)
        , t.lat = COALESCE(f.lat, t.lat )
        , t.lon = COALESCE(f.lon, t.lon )
        , t.elevation = COALESCE(f.elevation, t.elevation )
        , t.State= COALESCE(f.State, t.State)
        , t.zone = COALESCE(f.zone, t.zone )
        , t.city = COALESCE(f.city, t.city)
        , t.Country = COALESCE(f.Country, t.Country)
        , t.county = COALESCE(f.county, t.county)
        , t.descript = COALESCE(f.descript, t.descript )
        , t.district = COALESCE(f.district, t.district )
        , t.municipality = COALESCE(f.municipality, t.municipality )
        , t.region = COALESCE(f.region, t.region )
        FROM tributaries t, tributaries f 
        where t.main_lake_id = @toLake AND t.lake_id = @toLake 
        AND f.main_lake_id = @fromLake AND f.lake_id = @fromLake

    update [dbo].[lake_image] set lake_image_ownerid = @toLake where lake_image_ownerid = @fromLake
    update tributaries set main_lake_id = @toLake where main_lake_id <> lake_id AND main_lake_id = @fromLake  AND side NOT IN( 32, 16 )
    update tributaries set lake_id = @toLake where main_lake_id <> lake_id AND lake_id = @fromLake

    update tributaries set lake_id = @toLake where main_lake_id <> lake_id AND lake_id = @fromLake

    delete from tributaries where main_lake_id = @fromLake
    delete from tributaries where lake_id = @fromLake
    delete from lake where lake_id = @fromLake 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_update_fish_general' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_update_fish_general
GO

create PROCEDURE sp_update_fish_general @fish_id uniqueidentifier, @locked bit, @editor uniqueidentifier, @fish_description nvarchar(2048)
AS
SET NOCOUNT ON
BEGIN TRY  
    UPDATE dbo.fish Set stamp = GETUTCDATE(), locked = @locked, editor=@editor, descrip = @fish_description
        WHERE fish_id =  @fish_Id;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_update_interval' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_update_interval
GO

create PROCEDURE dbo.sp_update_interval @parent_id uniqueidentifier, @type int, @min float, @max float, @low float=null, @avg float=null, @high float=null
AS
SET NOCOUNT ON
BEGIN TRY  
    IF @parent_id IS NOt NULL AND @type IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT * FROM real_interval WHERE ri_parent_id = @parent_id AND ri_type = @type)
        BEGIN
            INSERT INTO real_interval (ri_parent_id, ri_type, ri_min, ri_max, ri_low, ri_avg, ri_high, ri_stamp)
                VALUES (@parent_id, @type, @min, @max, @low, @avg, @high, getdate())
        END
        ELSE
        BEGIN
            UPDATE real_interval SET ri_max=@max, ri_min=@min, ri_low = @low, ri_high = @high, ri_avg = @avg, ri_stamp=getdate()
                WHERE ri_parent_id = @parent_id AND ri_type = @type
        END
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_update_fish' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_update_fish
GO

-- 1 - sport, 2 - Coarse, 4 - commersial, 8 - invading, 128 - migrate pattern (inverted logic by default)
create PROCEDURE dbo.sp_update_fish @fish_Id uniqueidentifier
   , @habitat int,  @feedsOver int
   , @veL float, @veH float, @locked bit, @editor uniqueidentifier
   , @depthMin   float, @depthMax float
   , @react_color int
AS
SET NOCOUNT ON
BEGIN TRY  
    declare @instance_id uniqueidentifier = (SELECT TOP 1 id FROM dbo.fish_Rule WHERE fish_Id = @fish_Id AND periodStart = -1 AND periodEnd = -1);
    if( @instance_id is not null )
    BEGIN
        UPDATE dbo.fish_Rule SET  locked=@locked, editor=@editor, habitat = @habitat,  feedsOver = @feedsOver WHERE @instance_id = id
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_update_fish_spawn' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_update_fish_spawn
GO

/*
* save period settings for fish spawn
* called from SavePeriodSpawn
*/
create PROCEDURE sp_update_fish_spawn @fish_id uniqueidentifier, @spawn_period_start int, @spawn_period_end int
   , @spawn_at int, @spawn_over int, @locked bit, @editor uniqueidentifier
   , @veL float, @veH float, @depthMin   float, @depthMax float
   
AS
SET NOCOUNT ON
BEGIN TRY  
  IF ( @spawn_period_start BETWEEN 1 AND 12 ) AND ( @spawn_period_end BETWEEN @spawn_period_start AND 12)
  BEGIN
    UPDATE dbo.fish Set stamp = GETUTCDATE() WHERE fish_id =  @fish_Id;

    declare @instance_id uniqueidentifier = (SELECT TOP 1 id FROM dbo.fish_Rule WHERE fish_Id = @fish_Id AND periodStart <> -1 AND periodEnd <> -1);
    if( @instance_id is null )
    BEGIN
        INSERT INTO fish_Rule (fish_Id, periodStart, periodEnd, id) values (@fish_id, @spawn_period_start, @spawn_period_end, newid())
        SET @instance_id = (SELECT TOP 1 id FROM dbo.fish_Rule WHERE fish_Id = @fish_Id AND periodStart <> -1 AND periodEnd <> -1);
    END

    IF  @instance_id IS NOt NULL
    BEGIN
        UPDATE dbo.fish_Rule 
            SET periodStart = @spawn_period_start, periodEnd = @spawn_period_end, stamp = GETUTCDATE(), habitat = @spawn_at, spawnsOver = @spawn_over, locked = @locked, editor=@editor
            FROM dbo.fish_Rule WHERE fish_Id = @fish_Id AND periodStart <> -1 AND periodEnd <> -1
    END
  END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_save_fish_spawn_general' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_save_fish_spawn_general
GO

/*
* save general settings for fish spawn
* called from SaveGeneralSpawn
*/
create PROCEDURE sp_save_fish_spawn_general @fish_id uniqueidentifier, @age_female int, @age_male int, @egg_min int, @egg_max int
                                           , @desc nvarchar(max), @location nvarchar(max), @strategy nvarchar(max)
AS
SET NOCOUNT ON
BEGIN TRY  
    IF( NOT EXISTS (SELECT * FROM fish_spawn WHERE fish_id = @fish_id ))
    BEGIN
        INSERT INTO fish_spawn (fish_id, fish_spawn_age_female, fish_spawn_age_male
                  , fish_spawn_eggs_min, fish_spawn_eggs_max, fish_spawn_description, fish_spawn_location, reproductive_strategy)
            VALUES (@fish_id, @age_female, @age_male, @egg_min, @egg_max, @desc, @location, @strategy);
    END
    ELSE
    BEGIN
        UPDATE fish_spawn SET fish_spawn_age_female = @age_female, fish_spawn_age_male = @age_male
        , fish_spawn_eggs_min = @egg_min, fish_spawn_eggs_max = @egg_max
        , fish_spawn_description = @desc, fish_spawn_location = @location, reproductive_strategy=@strategy
        , fish_spawn_stamp = getdate() WHERE fish_id = @fish_id
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_weather_forecast16' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_weather_forecast16
GO

create PROCEDURE sp_weather_forecast16 @city_id int, @mli varchar(64),  @event int
       , @temp_day float, @temp_min float, @temp_max float, @temp_night float, @temp_eve float, @temp_morn float
       , @pressure float, @humidity float, @main varchar(64), @description varchar(255), @icon varchar(32)
       , @speed float, @win_degree int, @clouds int , @rain float
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON;
  DECLARE @return_value int = -1
    SET @temp_day = @temp_day - 273
    SET @temp_min = @temp_min - 273
    SET @temp_max = @temp_max - 273
    SET @temp_night = @temp_night - 273
    SET @temp_eve   = @temp_eve - 273
    SET @temp_morn  = @temp_morn - 273

    DECLARE @stamp datetime2 = ( SELECT dbo.UNIX_TIMESTAMP_TO_DATETIME(@event) );
    DECLARE @dt DATE = CAST( @stamp AS DATE )
    DECLARE @tm TIME = CAST(DATEADD(HOUR, DATEPART( HOUR,  @stamp ), '00:00:00') AS TIME)
     DECLARE @direction varchar(8) = ( SELECT dbo.fn_direction_by_win_degree( @win_degree ) )
    DECLARE @air_temperature smallint = ROUND(@temp_day, 0)
    
    SELECT @air_temperature = ROUND( ( CASE WHEN DATEPART( HOUR, @tm ) BETWEEN 4 AND 11 THEN @temp_morn
               WHEN DATEPART( HOUR, @tm ) BETWEEN 11 AND 16 THEN @temp_day
               WHEN DATEPART( HOUR, @tm ) BETWEEN 16 AND 23 THEN @temp_eve
               ELSE @temp_night END ), 0 );
    
    IF @dt = CAST(getdate() AS DATE)  
    BEGIN
        DELETE FROM weather_Forecast WHERE ( (dt = @dt) OR (dt < DATEADD(day, -10, getdate()) )) AND mli = @mli

        INSERT dbo.weather_Forecast( city_id,  mli, tmHigh,     tmLow,     tmDay,        humidity,  pressure, wind_max_speed,  wind_degree, rain_today,    wind_direction,  dt,  tm, icon, shortText, longText, air_temperature )
            VALUES ( @city_id, @mli, @temp_max, @temp_min, @temp_day, @humidity, @pressure, @speed, @win_degree, @rain, @direction, @dt, @tm, @icon, @main, @description, @air_temperature )
    END
        ELSE IF @dt > CAST(getdate() AS DATE)  
    BEGIN
        DELETE FROM weather_Forecast WHERE dt = @dt AND mli = @mli

        INSERT dbo.weather_Forecast( city_id,  mli, tmHigh,     tmLow,     tmDay,        humidity,  pressure, wind_max_speed,  wind_degree, rain_today,    wind_direction,  dt,  tm, icon, shortText, longText, air_temperature )
            VALUES ( @city_id, @mli, @temp_max, @temp_min, @temp_day, @humidity, @pressure, @speed, @win_degree, @rain, @direction, @dt, @tm, @icon, @main, @description, @air_temperature )
    END
    RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_weather_station' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_weather_station
GO

-- EXEC dbo.sp_weather_station 'CYQK', 2, 30, 37662, 49.783300, -94.366700, 11.107000, '05PE012'
create PROCEDURE sp_weather_station @name sysname, @type int, @status int, @weather_station_id uniqueidentifier, @lat float, @lon float, @wsid varchar(64)
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON;
  DECLARE @return_value int = -1
    
    IF NOT EXISTS ( SELECT * FROM Weather_station WHERE weather_station_id = @weather_station_id)
    BEGIN
      INSERT dbo.Weather_station ( weather_station_id,     weather_station_name, weather_station_type
                                 , weather_station_status, weather_station_lat,  weather_station_lon )
                          VALUES ( @weather_station_id,    @name, @type, @status, @lat, @lon )
      SET @return_value = @@ROWCOUNT;
    END
--    UPDATE WaterStation SET weather_station_id = @weather_station_id  WHERE @wsid = mli;                         
    RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spAddExtUser' AND xtype = 'P')
    DROP PROCEDURE dbo.spAddExtUser
GO

create PROCEDURE spAddExtUser @userName  varchar(64), @psw varchar(128),     @titul nvarchar(32)
    , @firstName nvarchar(64), @lastName nvarchar(64), @email varchar(128), @postal varchar(16)
    , @userId uniqueidentifier
AS
SET NOCOUNT ON
BEGIN TRY  
  DECLARE @hash bigint = NULL
  INSERT INTO Users( userName,  psw,                                 titul,  firstName,  lastName,  email
                   , postal,    access, question, answer, id ) 
            VALUES ( @userName, HashBytes('MD5', @psw + '*solt'),    @titul, @firstName, @lastName, @email
                   , @postal,   1,      N'Type your original email', HashBytes('MD5', @email + '+zuker'), @userId )
  SELECT @hash = CAST(psw AS bigint) FROM Users WHERE id =  @userId
  IF @hash IS NOT NULL
    SELECT @userId AS userId, @hash AS [hash]
  ELSE
    SELECT '00000000-0000-0000-0000-000000000000' AS userId, 0 AS [hash]
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spAddUser' AND xtype = 'P')
    DROP PROCEDURE dbo.spAddUser
GO

create PROCEDURE spAddUser @userName  varchar(64), @psw varchar(128),     @titul nvarchar(32)
    , @firstName nvarchar(64), @lastName nvarchar(64), @email varchar(128), @postal varchar(16)
    , @subs BIT, @question nvarchar(64), @answer nvarchar(64), @cell bigint, @userId uniqueidentifier OUT
AS
SET NOCOUNT ON
BEGIN TRY  
  SET @userId = NULL
  DECLARE @tmp TABLE( id uniqueidentifier )
  INSERT INTO Users( userName, psw, titul, firstName, lastName, email, postal, subs, question, answer, cell ) 
  OUTPUT INSERTED.ID INTO @tmp( id )
                     VALUES ( @userName, HashBytes('MD5', @psw + '*solt'), @titul, @firstName, @lastName, @email
                     , @postal, @subs, @question, HashBytes('MD5', @answer + '+zuker'), @cell )
  IF EXISTS (SELECT * FROM @tmp ) 
    SELECT TOP 1 @userId = id FROM @tmp
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spPushSpeciesFromLakeToStation' AND xtype = 'P')
    DROP PROCEDURE dbo.spPushSpeciesFromLakeToStation
GO

-- exec spPushSpeciesFromLakeToStation 
create PROCEDURE spPushSpeciesFromLakeToStation 
WITH EXEC AS CALLER
AS
BEGIN TRY  
  SET NOCOUNT ON;
  DECLARE @return_value int = -1
    -- push fishes from lakes to station place
    insert dbo.fish_location (station_Id, fish_Id, probability, today )
        select id, fish_Id, today, today FROM
        (
            select id, fish_Id, max(today) AS today FROM
            (
              select w.id, f.fish_Id, probability, 
                (CASE [probability_source_type] WHEN 0 then 100 when 1 then 90 when 2 then 75 when 4 then 50 else 0 end) as today
                from  [dbo].[lake_fish] f
                  join [dbo].[WaterStation] w on (w.[lakeId]  = f.[lake_id] )
            )b  group by  id, fish_Id
        ) a
        WHERE NOT EXISTS (SELECT * FROM fish_location fl WHERE fl.station_Id = a.id AND fl.fish_Id = a.fish_Id)
    SET @return_value = @@ROWCOUNT;
    RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spSaveUser' AND xtype = 'P')
    DROP PROCEDURE dbo.spSaveUser
GO

create PROCEDURE spSaveUser @ipaddr varchar(32), @agent varchar(128)
    , @addr varchar(32), @host varchar(255), @user varchar(255), @email varchar(255), @country char(2)
    , @postal varchar(16), @fname nvarchar(64), @lname nvarchar(64), @psw varchar(128)
AS
SET NOCOUNT ON
BEGIN TRY  
    INSERT INTO Users (userName, email, ipaddr, agent, addr, host, country, postal, firstName, lastName, psw, question, answer) 
        VALUES (@user, @email, @ipaddr, @agent, @addr, @host, @country, @postal, @fname, @lname, HashBytes('MD5', @psw + '*solt'), 'dog', 0x0024);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_fish_image' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_fish_image
GO

/******
 * on page EditFishZoo save image to fish_image and set id to repalted form table: fish_zoo
 * depend on fn_river_view
 *
 * INPUT PARAMETERS:
 *
 *    @@lake_id   uniqueidentifier  - a lake guid
 *    @image      image             - actual image
 *    @tablename  sysname           - this table will be update to related id
 *    @colname    sysname           - this @tablename.column will be update to related id
 *
 *  Usage: 
            EXEC sp_add_fish_image 'C2E8C307-F470-458B-8CEE-000999277126', 0xFF, N'fish_zoo', N'fish_zoo_image', 1, N'source', N'author', N'www.ca', N'label', N'location', 40, -80, N'tag', getdate()
 */
/*
 select * from fish_image 
 delete from fish_image where fish_id = 'C2E8C307-F470-458B-8CEE-000999277126'
 update fish_zoo set [fish_zoo_image] = null
*/
CREATE PROCEDURE dbo.sp_add_fish_image @fish_id uniqueidentifier, @image varbinary(max),  @tablename sysname,  @colname sysname
, @gender bit, @source nvarchar(255), @author nvarchar(255), @link nvarchar(255), @label nvarchar(255)
, @location nvarchar(255), @lat float, @lon float, @tag nvarchar(255), @stamp nvarchar(255)
AS
SET NOCOUNT ON
BEGIN TRY  
  if @fish_Id IS NOT NULL 
  BEGIN
        INSERT INTO dbo.fish_image( fish_id, fish_image_pic, fish_image_gender, fish_image_source, fish_image_author
            , fish_image_link, fish_image_label, fish_image_location, fish_image_lat, fish_image_lon, fish_image_tag, fish_image_stamp, fish_image_hash )
         VALUES (@fish_Id, @image, @gender, @source, @author
           , @link, @label, @location, @lat, @lon, @tag, @stamp, HASHBYTES('SHA1', @image) );

    If EXISTS (SELECT * FROM sys.tables WHERE name = @tablename) AND EXISTS (SELECT * FROM sys.columns WHERE name = @colname)
    BEGIN
        declare @execsql sysname = N'UPDATE ' + @tablename + N' SET ' + @colname + N'= ' + CAST(SCOPE_IDENTITY() AS sysname) + N' WHERE fish_id=''' + CAST(@fish_id AS sysname) + '''';
        EXEC ( @execsql );
    END
  END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_PlotSource' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_PlotSource
GO

-- exec sp_PlotSource 123, '2CFFB500-3E59-4120-9460-055856E9AC5C'
CREATE procedure dbo.sp_PlotSource @sid int, @fish varchar(64)
as
BEGIN TRY  
  SET NOCOUNT ON
  DECLARE @rst TABLE (dt datetime, tm float default(0), lvl float default(0), prc float default(0), dis float default(0));
  DECLARE @line varchar(max) = '?([';

  DECLARE @start date = DATEADD( DAY, -10, GETDATE());
  DECLARE @end date = DATEADD( DAY,  10, GETDATE());
  DECLARE @mli varchar(64), @WaterStation uniqueidentifier;
  SELECT TOP 1 @mli = MLI FROM WaterStation WHERE sid = @sid;
  INSERT INTO @rst (dt) SELECT * from dbo.GetDatePeriod( @start, @end );

  UPDATE t SET t.tm = tmHigh, t.prc = f.rain_today FROM @rst t JOIN weather_Forecast f ON (f.dt = t.dt) WHERE f.mli = @mli;
  UPDATE t SET t.lvl = elevation FROM @rst t JOIN WaterData f ON CAST(f.stamp AS DATE) = t.dt 
    WHERE f.mli = @mli and ( elevation is not null OR discharge is not null);

  SELECT @line = @line + '[Date.UTC(' + REPLACE(CONVERT(DATE, dt, 126), '-', ',') + '),' + CAST(tm AS varchar(16)) + '],' FROM @rst ORDER BY dt ASC
  SET @line = LEFT(@line, LEN(@line)-1) + ']);'

  SELECT @line
  RETURN
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_update_fish_zoo' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_update_fish_zoo
GO

CREATE PROCEDURE dbo.sp_update_fish_zoo @fish_id uniqueidentifier, @locked bit, @editor uniqueidentifier
   , @max_length float, @max_weight float, @avg_length float, @avg_weight float, @natural_color int, @longevity int
   , @fin nvarchar(max), @body nvarchar(max), @counts nvarchar(max), @shape nvarchar(max), @em nvarchar(max), @im nvarchar(max)
   
AS
SET NOCOUNT ON
BEGIN TRY  
  if @fish_Id IS NOT NULL 
  BEGIN
    UPDATE dbo.fish Set stamp = GETUTCDATE() WHERE fish_id =  @fish_Id;

    IF NOT EXISTS (SELECT * FROM dbo.fish_zoo WHERE fish_Id = @fish_Id)
    BEGIN
        INSERT INTO dbo.fish_zoo( fish_id, fish_max_length, fish_avg_length, fish_max_weight, fish_avg_weight
            , natural_color, longevity, fin, body, counts, shape, external_morphology, internal_morphology  )
         VALUES (@fish_Id, @max_length, @avg_length, @max_weight, @avg_weight, @natural_color, @longevity, @fin, @body, @counts, @shape, @em, @im );
    END
    ELSE
    BEGIN
        UPDATE dbo.fish_zoo SET fish_max_length=@max_length, fish_avg_length=@avg_length, fish_max_weight=@max_weight, fish_avg_weight=@avg_weight
          , natural_color = @natural_color, longevity = @longevity, fin = @fin
           , body = @body, counts = @counts, shape = @shape, external_morphology = @em, internal_morphology = @im 
          WHERE fish_Id = @fish_Id
    END
  END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_lake' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_lake
GO
-- to add new lakes/rivers
CREATE PROCEDURE dbo.sp_add_lake @lake_name sysname, @type int, @country char(2), @state char(2), @county nvarchar(64)
AS
SET NOCOUNT ON
BEGIN TRY  
    set @lake_name = RTRIM(LTRIM(@lake_name))
    insert into lake (lake_id, [locType], [lake_name], alt_name ) values (newid(), @type, @lake_name, null)

    declare @lake_id uniqueidentifier = (select TOP 1 lake_id from lake where lake_name = @lake_name ORDER BY stamp DESC);
    update Tributaries set country=@country, state=@state , county = @county  where side = 16 AND [Main_Lake_id]=Lake_id 
        and Lake_id = @lake_id ;
    select @lake_id, (select lake_name from lake where lake_id=@lake_id);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_save_lake' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_save_lake
GO
-- declare @link_list xml = CAST(N'<a>0a194de0-2892-e811-9104-00155d007b12</a><a>4f174d22-1c54-43ec-8f0d-eb8e80b7b25a</a><a>e31e6d05-fe6c-48b2-9b66-f36423812d61</a>' AS XML);
-- to link lakes/rivers
-- exec sp_save_lake '64cf30df-2892-e811-9104-00155d007b12'
CREATE PROCEDURE dbo.sp_save_lake @lake_id uniqueidentifier
AS
SET NOCOUNT ON
BEGIN TRY  
    IF @lake_id = NULL
        RETURN
    IF EXISTS (SELECT * FROM Tributaries WHERE lake_id = main_lake_id AND lake_id = @lake_id AND side = 16 )  -- source
    BEGIN
        DECLARE @source uniqueidentifier = (SELECT source FROM Lake WHERE lake_id = @lake_id );
        IF @source IS NOT NULL
        BEGIN
            UPDATE Tributaries SET main_lake_id = @source WHERE main_lake_id = lake_id AND lake_id = @lake_id AND side = 16 

            IF NOT EXISTS( SELECT * FROM Tributaries WHERE main_lake_id <> lake_id AND lake_id = @source )
            BEGIN
                INSERT INTO Tributaries (main_lake_id, lake_id, side) VALUES (@source, @lake_id, 64)    -- unknown status
            END
        END
    END ELSE
    BEGIN       -- INSERT instance
        INSERT INTO Tributaries (main_lake_id, lake_id, side) VALUES (@source, @lake_id, 16)
    END
    IF NOT EXISTS (SELECT * FROM Tributaries WHERE lake_id = main_lake_id AND lake_id = @lake_id AND side = 32 )  -- mouth
    BEGIN
        INSERT INTO Tributaries (main_lake_id, lake_id, side) VALUES (@source, @lake_id, 32)
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'sp_add_lake_shape' AND xtype = 'P')
    DROP PROCEDURE dbo.sp_add_lake_shape
GO
CREATE PROCEDURE sp_add_lake_shape @lake_id uniqueidentifier, @sourceLat float, @sourceLon float, @mouthLat float, @mouthLon float, @state char(2), @location nvarchar(255), @shape nvarchar(max), @num int
WITH EXEC AS CALLER
AS
BEGIN TRY  
  BEGIN TRANSACTION;  
  SET NOCOUNT ON;
  UPDATE Tributaries SET lat = @sourceLat, lon = @sourceLon, [State]=@state, Country='CA' WHERE ( lat IS NULL OR lon IS NULL ) AND side IN (16, 32) AND Lake_id = @lake_id AND Lake_id = Main_Lake_id
  SET @location = RTRIM(@location)

  IF LEN(@location) > 1
      UPDATE Tributaries SET [location] = @location WHERE [location] IS NULL AND side IN (16, 32) AND Lake_id = @lake_id AND Lake_id = Main_Lake_id

  IF DATALENGTH(@shape) > 1 AND @num > 2
  BEGIN
    insert into Lake_Shape (lake_id, Lake_Shape_stamp, Lake_Shape_shape, Lake_Shape_hash)
        SELECT lake_id, getdate(), Lake_Shape_shape, CAST(HashBytes('MD5', Lake_Shape_shape.ToString()) as bigint)
            FROM (SELECT @lake_id AS lake_id, geography::STGeomFromText( 'LINESTRING('+ @shape + ')' , 4326) AS Lake_Shape_shape)x
  END
  COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0  
        ROLLBACK TRANSACTION;  
    declare @ErrorMessage sysname = ERROR_MESSAGE(), @ErrorSeverity int = ERROR_SEVERITY(), @ErrorState int = ERROR_STATE();
    SELECT ERROR_NUMBER()    AS ErrorNumber,    @ErrorSeverity, @ErrorState, ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE() AS ErrorLine,  @ErrorMessage;
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;     
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spAddFish' AND type = 'P')
    DROP PROCEDURE dbo.spAddFish
GO
-- EXEC spAddFish '0c5d1cc6-849c-20c3-cf02-6258e4e37990', 734, '', 0
-- SELECT * FROM fish where sid = 734
CREATE PROCEDURE spAddFish @lakeid uniqueidentifier, @fishid int, @link nvarchar(512), @trustLevel int, @status tinyint, @method nvarchar(max)
AS
SET NOCOUNT ON
BEGIN TRY
   DECLARE @probability int = 10
   IF @trustLevel = 0  SET @probability = 100
   IF @trustLevel = 1  SET @probability = 80
   IF @trustLevel = 2  SET @probability = 65
   IF @trustLevel = 3  SET @probability = 30

   IF LEN(ISNULL(@link, '')) = 0 SET @link = (SELECT TOP 1 link FROM lake_fish ORDER BY created DESC)
 
  INSERT INTO lake_fish( Lake_id,fish_id,link,probability,probability_source_type,created, status, method ) 
	SELECT @lakeid, fish_id, @link, @probability, @trustLevel, GETDATE(), @status, @method FROM fish f WHERE sid = @fishid
		AND NOT EXISTS (SELECT * FROM lake_fish l WHERE lake_id = @lakeid AND f.fish_id = l.fish_id)
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_del_river' AND type = 'P')
    DROP PROCEDURE dbo.sp_del_river
GO
CREATE PROCEDURE [dbo].[sp_del_river]  @lake_id uniqueidentifier 
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    DELETE FROM Parking_Spot WHERE @lake_id = lake_id
    DELETE FROM lake_fish WHERE @lake_id = lake_id
    DELETE FROM dbo.Tributaries  WHERE @lake_id = Main_Lake_id OR  @lake_id = Lake_id
	DELETE FROM lake  WHERE @lake_id = lake_id
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_add_tributary' AND type = 'P')
    DROP PROCEDURE dbo.sp_add_tributary
GO
/*
    @main_lake_id - could be  a river throu @lake_id
*/
CREATE PROCEDURE sp_add_tributary @main_lake_id uniqueidentifier, @lake_id uniqueidentifier, @type int, @lat float = NULL, @lon float = NULL
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON
    DECLARE @loctype int =  (SELECT locType FROM lake WHERE lake_id = @lake_id);
    IF @type = 1   -- link to lake
	BEGIN
        INSERT INTO Tributaries ([Main_Lake_id], [Lake_id], side, lat, lon) VALUES (@main_lake_id, @lake_id, 1, @lat, @lon ); 
	END ELSE
	IF  @loctype IN (1, 8, 8192)
	BEGIN
		DECLARE @srcid int = (SELECT TOP 1 id FROM  Tributaries WHERE side = 16 AND main_lake_id = @lake_id AND main_lake_id=lake_id)
		DECLARE @mthid int = (SELECT TOP 1 id FROM  Tributaries WHERE side = 32 AND main_lake_id = @lake_id AND main_lake_id=lake_id)
	   IF @type = 2 
	   BEGIN
           IF @srcid Is NOT NULL
                INSERT INTO Tributaries (main_lake_id, lake_id, side, lat, lon) VALUES (@lake_id, @main_lake_id, 4, @lat, @lon);
           ELSE
		        UPDATE Tributaries SET lake_id = @main_lake_id, lat = @lat, lon = @lon, side = 4 WHERE id = @srcid AND @srcid IS NOT NULL

           IF @srcid Is NOT NULL
               INSERT INTO Tributaries (main_lake_id, lake_id, side, lat, lon) VALUES (@lake_id, @main_lake_id, 8, @lat, @lon);
           ELSE
    		   UPDATE Tributaries SET lake_id = @main_lake_id, lat = @lat, lon = @lon, side = 8 WHERE id = @mthid AND @mthid IS NOT NULL
	   END ELSE
	   IF @type = 4
	   BEGIN
           IF @srcid Is NOT NULL
                INSERT INTO Tributaries (main_lake_id, lake_id, side, lat, lon) VALUES (@lake_id, @main_lake_id, 4, @lat, @lon);
           ELSE
		        UPDATE Tributaries SET lake_id = @main_lake_id, lat = @lat, lon = @lon, side = 4 WHERE id = @srcid AND @srcid IS NOT NULL
	   END ELSE
	   IF @type = 8
	   BEGIN
           IF @srcid Is NOT NULL
               INSERT INTO Tributaries (main_lake_id, lake_id, side, lat, lon) VALUES (@lake_id, @main_lake_id, 8, @lat, @lon);
           ELSE
    		   UPDATE Tributaries SET lake_id = @main_lake_id, lat = @lat, lon = @lon, side = 8 WHERE id = @mthid AND @mthid IS NOT NULL
	   END
	END 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_assign_border' AND type = 'P')
    DROP PROCEDURE dbo.sp_assign_border
GO
/*
    when assign mouth or source the exchange lat/lon if missed
    called from FishTracker.Editor.EditLakeLink.ButtonSubmit_Click
*/
CREATE PROCEDURE sp_assign_border @lake_id uniqueidentifier
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
    UPDATE LAKE SET stamp = getdate() WHERE lake_id = @lake_id
    -- set source/mouth if mouth/source was assigned
    UPDATE l SET lake_id = @lake_id FROM Tributaries l JOIN Tributaries t ON t.Main_Lake_id = @lake_id AND t.Lake_id = l.Main_Lake_id
        WHERE EXISTS (SELECT * FROM lake where locType IN (1,8,256) AND lake.lake_id = l.Main_Lake_id)
            AND l.Main_Lake_id = l.lake_id AND l.side IN (16,32) AND t.side IN (16,32) AND l.side <> t.side 
    -- se lat/lon
    UPDATE t SET t.lat = COALESCE(t.lat, m.lat), t.lon = COALESCE(t.lon, m.lon)
        FROM Tributaries t 
        JOIN ( SELECT * FROM Tributaries WHERE Main_Lake_id = @lake_id AND side IN (16,32) )m 
            ON t.Main_Lake_id = m.lake_id AND t.side <> m.side
        WHERE t.side IN (16,32)
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_exchange_latlon' AND type = 'P')
    DROP PROCEDURE dbo.sp_exchange_latlon
GO
/*
   exchange src/mnth ..  used only in MSSQLSMS mode
*/
CREATE PROCEDURE sp_exchange_latlon @lake_id uniqueidentifier
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
 DECLARE @slat float, @slon float, @mlat float, @mlon float 
 select @slat = lat, @slon = lon from [Tributaries] where Main_Lake_id=Lake_id and side = 32 and Main_Lake_id = @lake_id
 select @mlat = lat, @mlon = lon from [Tributaries] where Main_Lake_id=Lake_id and side = 16 and Main_Lake_id = @lake_id
 update [Tributaries] set lat= @slat, lon = @slon WHERE Main_Lake_id=Lake_id and side = 16 and Main_Lake_id = @lake_id
 update [Tributaries] set lat= @mlat, lon = @mlon WHERE Main_Lake_id=Lake_id and side = 32 and Main_Lake_id = @lake_id
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_build_regulations' AND type = 'P')
    DROP PROCEDURE dbo.sp_build_regulations
GO
/*
   extract dor for river regulations in xml format
   Usage: EXEC sp_build_regulations '0c369d7b-849c-20c3-6274-0fd28a9dbbf4'
   Link:   https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf
   Source: https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1
*/
CREATE PROCEDURE sp_build_regulations @lake_id uniqueidentifier
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
    DECLARE @locType int, @lake_name sysname, @link nvarchar(1024), @IsFish bit, @regulations nvarchar(255), @link_reg nvarchar(255), @noFish bit

    SELECT @locType=locType, @lake_name=lake_name, @link=link, @IsFish=IsFish, @regulations=regulations, @link_reg=link_reg, @noFish=noFish 
        FROM lake v LEFT JOIN Tributaries t ON v.lake_id = t.Lake_id AND t.side IN (16, 32)
        WHERE v.lake_id = @lake_id;

    DECLARE @rg XML = (SELECT * FROM dbo.fn_GetLakeRegulations( @lake_id ) WHERE lake_id = @lake_id FOR XML AUTO)

    IF @lake_name IS NOt NULL
    BEGIN
        DECLARE @rs XML = (SELECT lake_id, @locType AS locType, @lake_name AS lake_name, @link AS link, @IsFish AS IsFish
            , @regulations AS regulations, @link_reg AS link_reg, @noFish AS noFish FROM lake WHERE lake_id = @lake_id FOR XML AUTO, BINARY BASE64)
        IF @rs IS NOT NULL
        BEGIN
          SELECT CAST( COALESCE(CAST(@rs AS nvarchar(MAX)), '') + COALESCE(CAST(@rg AS nvarchar(MAX)), '') AS xml) AS doc;
        END
    END
    RETURN @@ROWCOUNT      
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_delete_with_cascade' AND type = 'P')
    DROP PROCEDURE dbo.sp_delete_with_cascade
GO
/* 
Recursive row delete procedure. 

It deletes all rows in the table specified that conform to the criteria selected, 
while also deleting any child/grandchild records and so on.  This is designed to do the 
same sort of thing as Access's cascade delete function. It first reads the sysforeignkeys 
table to find any child tables, then deletes the soon-to-be orphan records from them using 
recursive calls to this procedure. Once all child records are gone, the rows are deleted 
from the selected table.   It is designed at this time to be run at the command line. It could 
also be used in code, but the printed output will not be available.
*/
CREATE PROCEDURE dbo.sp_delete_with_cascade
(
@cTableName varchar(50), /* name of the table where rows are to be deleted */
@cCriteria nvarchar(1000) /* criteria used to delete the rows required */
)
As
BEGIN
SET NOCOUNT ON
declare     @cTab varchar(255), /* name of the child table */
    @cCol varchar(255), /* name of the linking field on the child table */
    @cRefTab varchar(255), /* name of the parent table */
    @cRefCol varchar(255), /* name of the linking field in the parent table */
    @cFKName varchar(255), /* name of the foreign key */
    @cSQL nvarchar(1000), /* query string passed to the sp_ExecuteSQL procedure */
    @cChildCriteria nvarchar(1000) /* criteria to be used to delete 
                                           records from the child table */


/* declare the cursor containing the foreign key constraint information */
DECLARE cFKey CURSOR LOCAL FOR 
SELECT SO1.name AS Tab, 
       SC1.name AS Col, 
       SO2.name AS RefTab, 
       SC2.name AS RefCol, 
       FO.name AS FKName
FROM dbo.sysforeignkeys FK  
INNER JOIN dbo.syscolumns SC1 ON FK.fkeyid = SC1.id 
                              AND FK.fkey = SC1.colid 
INNER JOIN dbo.syscolumns SC2 ON FK.rkeyid = SC2.id 
                              AND FK.rkey = SC2.colid 
INNER JOIN dbo.sysobjects SO1 ON FK.fkeyid = SO1.id 
INNER JOIN dbo.sysobjects SO2 ON FK.rkeyid = SO2.id 
INNER JOIN dbo.sysobjects FO ON FK.constid = FO.id
WHERE SO2.Name = @cTableName

OPEN cFKey
FETCH NEXT FROM cFKey INTO @cTab, @cCol, @cRefTab, @cRefCol, @cFKName
WHILE @@FETCH_STATUS = 0
     BEGIN
    /* build the criteria to delete rows from the child table. As it uses the 
           criteria passed to this procedure, it gets progressively larger with 
           recursive calls */
    SET @cChildCriteria = @cCol + ' in (SELECT [' + @cRefCol + '] FROM [' + 
                              @cRefTab +'] WHERE ' + @cCriteria + ')'
    /* call this procedure to delete the child rows */
    EXEC sp_delete_with_cascade @cTab, @cChildCriteria 
    FETCH NEXT FROM cFKey INTO @cTab, @cCol, @cRefTab, @cRefCol, @cFKName
     END
Close cFKey
DeAllocate cFKey
/* finally delete the rows from this table and display the rows affected  */
SET @cSQL = 'DELETE FROM [' + @cTableName + '] WHERE ' + @cCriteria
/* change NOCOUNT option as smartgwt as complains if there is no count returned */
SET NOCOUNT OFF
EXEC sp_ExecuteSQL @cSQL;
END;
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_sys_update_loc' AND type = 'P')
    DROP PROCEDURE dbo.sp_sys_update_loc
GO
 
CREATE PROCEDURE sp_sys_update_loc @line sysname, @loc sysname, @district sysname
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
	update [Tributaries] set [district] = @district, location = @loc  where TRIM(@line) in (location, [district])

	update [Tributaries] set location = @district, [district] = @loc  where [district] = @loc
 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 
/*
declare @data xml = (SELECT * FROM OPENROWSET(BULK N'k:\temp\path.xml', SINGLE_CLOB) rs);

EXEC sp_push_us_water_data '08313000', 'NY', 'Streamflow', 'ft^2/s', '<root><a d="2020-09-12" v="2.70" /><a d="2020-09-13" v="2.72" /></root>'
EXEC sp_push_us_water_data '08313000', 'NY', 'Gage height', 'ft', '"<root><a d="2020-09-12" v="2.70" /><a d="2020-09-13" v="2.72" /></root>'
select * from waterdata where mli = '08313000'
*/
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_push_us_water_data' AND type = 'P')
    DROP PROCEDURE dbo.sp_push_us_water_data
GO

/*
	parse XML data FROM USGS water data center
*/
 
CREATE PROCEDURE dbo.sp_push_us_water_data @mli sysname, @state sysname, @name sysname, @unit varchar(64),  @xmldoc XML
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
	IF DATALENGTH(@xmldoc) = 0 OR LEN(@mli) = 0 OR LEN(@state) = 0
		RETURN;

	IF NOT EXISTS (SELECT * FROM UScode WHERE name like @name AND unit LIKE @unit)
		INSERT INTO UScode (name, unit) VALUES (@name , @unit)

	DECLARE @koef_elevation float = (CASE WHEN @unit IN ('ft', ' in ft', ' feet') THEN 0.3048000097536 ELSE 1 END);
	DECLARE @koef_discharge float = (
		CASE WHEN @unit = 'ft^3/s'  THEN 101.941  
		     WHEN @unit = 'gal/min' THEN 350.227125 
			                        ELSE 1            -- [m^3/hr] 
		END);
	DECLARE @koef_velocity float = (
		CASE WHEN @unit IN ('ft/s', ' feet per second') THEN 101.941  
		     WHEN @unit = 'miles per hour'  THEN 0.44704 ELSE 1 
		END);

	;WITH cte AS
	 (
		SELECT dt
			, CASE WHEN @name in ( 'Streamflow')  THEN val ELSE NULL END							   AS discharge	-- [m^3/hr]
			, CASE WHEN @name in ('Water velocity reading from field sensor'
								, 'Mean water velocity for discharge computation' )  
								THEN val ELSE NULL END												   AS velocity  -- [m/s] 
			, CASE WHEN @name in ( 'Gage height', 'Stream water level elevation above NAVD 1988', 'Elevation of reservoir water surface above datum'
								 , 'Lake or reservoir elevation above United States Bureau of Reclamation Klamath Basin (USBRKB) Datum'
								 , 'Lake or reservoir water surface elevation above NAVD 1988'
								 , 'Lake or reservoir water surface elevation above NGVD 1929'
								 , 'Estuary or ocean water surface elevation above NAVD 1988'
								 , 'Stream water level elevation above NGVD 1929'
								 , 'Estuary or ocean water surface elevation above NGVD 1929'
								 , 'Lake or reservoir water surface elevation above NGVD 1929'
								 , 'Lake or reservoir elevation above New York State Barge Canal Datum (NYBCD)') THEN val ELSE NULL END AS elevation  -- [m]
			, CASE WHEN @name = 'Temperature' AND @unit = 'Water'  THEN val ELSE NULL END			    AS temperature
			, CASE WHEN @name in ( 'Turbidity')  THEN val ELSE NULL END							        AS turbidity	-- 

			, CASE WHEN @name = 'Barometric pressure'  THEN val ELSE NULL END						    AS pressure
			, CASE WHEN @name in ('Wind speed', 'Wind gust speed')  THEN val ELSE NULL END				AS wind
			, CASE WHEN @name = 'Temperature' AND @unit = 'Air'  THEN val ELSE NULL END			        AS air
			, CASE WHEN @name in ('Wind direction', 'Wind gust direction') THEN val ELSE NULL END       AS winddir
			, CASE WHEN @name = 'Relative humidity' THEN val ELSE NULL END						        AS humidity
			, CASE WHEN @name = 'Precipitation' THEN val ELSE NULL END						            AS precipitation

			, CASE WHEN @name in ('Chlorophylls', 'Chlorophyll <i>a</i>')  THEN val ELSE NULL END		AS chlorophylls
			, CASE WHEN @name = 'Phycocyanins (cyanobacteria)'  THEN val ELSE NULL END					AS phycocyanins
			, CASE WHEN @name = 'Cyanobacteria (blue-green algae)'  THEN val ELSE NULL END				AS cyanobacteria
			, CASE WHEN @name = 'Phycoerythrin (blue-green algae)'  THEN val ELSE NULL END				AS phycoerythrin
			, CASE WHEN @name = 'Orthophosphate'  THEN val ELSE NULL END								AS orthophosphate
			, CASE WHEN @name = 'Nitrate'  THEN val ELSE NULL END										AS nitrate
			, CASE WHEN @name = 'Chloride'  THEN val ELSE NULL END										AS chloride
			, CASE WHEN @name = 'Dissolved oxygen'  THEN val ELSE NULL END								AS oxygen
			, CASE WHEN @name = 'pH'  THEN val ELSE NULL END											AS ph
			, CASE WHEN @name = 'Salinity'  THEN val ELSE NULL END							        	AS salinity
			FROM
		(
			SELECT X.C.value(N'@d', N'date') as dt,   X.C.value(N'@v', N'float') as val
				FROM (SELECT @xmldoc AS XML_DATA) DATA CROSS APPLY DATA.XML_DATA.nodes(N'/root/a') as X(C)
		)x
	)
	MERGE INTO WaterData AS t
        USING cte AS source ON CAST(t.stamp AS DATE ) = source.dt AND t.mli = @mli
    WHEN MATCHED THEN 
        UPDATE SET t.discharge = COALESCE(source.discharge * @koef_discharge,   t.discharge)
		, t.elevation          = COALESCE(source.elevation * @koef_elevation,   t.elevation)
		, t.velocity           = COALESCE(source.velocity  * @koef_velocity,	t.velocity)
		, t.temperature        = COALESCE(source.temperature,					t.temperature)
		, t.turbidity          = COALESCE(source.turbidity,				    	t.turbidity)

		, t.pressure           = COALESCE(source.pressure,						t.pressure)
		, t.air                = COALESCE(source.air,							t.air)
		, t.wind               = COALESCE(source.wind,							t.wind)
		, t.winddir            = COALESCE(source.winddir,						t.winddir)
		, t.humidity           = COALESCE(source.humidity,						t.humidity)
		, t.precipitation      = COALESCE(source.precipitation,					t.precipitation)

		, t.chlorophylls       = COALESCE(source.chlorophylls,					t.chlorophylls)
		, t.phycocyanins       = COALESCE(source.phycocyanins,					t.phycocyanins)
		, t.cyanobacteria      = COALESCE(source.cyanobacteria,					t.cyanobacteria)
		, t.phycoerythrin      = COALESCE(source.phycoerythrin,					t.phycoerythrin)
		, t.orthophosphate     = COALESCE(source.orthophosphate,				t.orthophosphate)
		, t.nitrate            = COALESCE(source.nitrate,						t.nitrate)
		, t.chloride           = COALESCE(source.chloride,						t.chloride)
		, t.oxygen             = COALESCE(source.oxygen,						t.oxygen)
		, t.salinity           = COALESCE(source.salinity,						t.salinity)
		, t.ph                 = COALESCE(source.ph,							t.ph)
    WHEN NOT MATCHED BY TARGET THEN  
        INSERT (stamp, discharge, elevation, mli,  pressure, chlorophylls, salinity, phycocyanins, phycoerythrin, cyanobacteria, orthophosphate, nitrate, chloride, wind, temperature, oxygen, ph, velocity, winddir, humidity, precipitation) 
		VALUES ( dt,  discharge,  elevation, @mli, pressure, chlorophylls, salinity, phycocyanins, phycoerythrin, cyanobacteria, orthophosphate, nitrate, chloride, wind, temperature, oxygen, ph, velocity, winddir, humidity, precipitation );
	RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;  
GO 

------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_ows_meteo' AND type = 'P')
    DROP PROCEDURE dbo.sp_ows_meteo
GO

/*
	Procedure parse JSON doc and then insert into diffrent tables:
	1. WaterStation - meteo from water station
	2. weather_Forecast

		called from [TR_ows_meteo]
*/
CREATE PROCEDURE dbo.sp_ows_meteo @js nvarchar(max), @mli varchar(64), @link uniqueidentifier
AS
SET NOCOUNT ON
BEGIN TRY
	IF @js IS NULL OR @mli IS NULL
	RETURN

declare @moonPhaseCode varchar(max) = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.moonPhaseCode'), '[',''), ']',''));
declare @moonPhaseDay varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.moonPhaseDay'), '[',''), ']',''));
declare @narrative varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.narrative'), '[',''), ']',''));
declare @qpf varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.qpf'), '[',''), ']',''));
declare @qpfSnow varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.qpfSnow'), '[',''), ']',''));
declare @sunriseTimeLocal varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.sunriseTimeLocal'), '[',''), ']',''));
declare @sunsetTimeLocal varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.sunsetTimeLocal'), '[',''), ']',''));
declare @temperatureMax varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.temperatureMax'), '[',''), ']',''));
declare @temperatureMin varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.temperatureMin'), '[',''), ']',''));
declare @validTimeLocal varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.validTimeLocal'), '[',''), ']',''));
declare @cloudCover varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].cloudCover'), '[',''), ']',''));
declare @dayOrNight varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].dayOrNight'), '[',''), ']',''));
declare @iconCode varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].iconCode'), '[',''), ']',''));
declare @iconCodeExtend varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].iconCodeExtend'), '[',''), ']',''));
declare @info varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].narrative'), '[',''), ']',''));
declare @precipChance varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].precipChance'), '[',''), ']',''));
declare @precipType varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].precipType'), '[',''), ']',''));
declare @qpf0 varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].qpf'), '[',''), ']',''));
declare @qpfSnow0 varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].qpfSnow'), '[',''), ']',''));
declare @qualifierPhrase varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].qualifierPhrase'), '[',''), ']',''));
declare @relativeHumidity varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].relativeHumidity'), '[',''), ']',''));
declare @air_temperature varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].temperature'), '[',''), ']',''));
declare @wind_degree varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].windDirection'), '[',''), ']',''));
declare @win_dir_cardinal varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].windDirectionCardinal'), '[',''), ']',''));
declare @wind_max_speed varchar(max)  = (SELECT  REPLACE(REPLACE(JSON_QUERY(@js,'$.daypart[0].windSpeed'), '[',''), ']',''));
	
declare @tbl TABLE (id int not null, narrative varchar(255), qpf float, qpfSnow float
	, sunriseTimeLocal DATETIME2, sunsetTimeLocal DATETIME2, temperatureMax float, temperatureMin float, validTimeLocal DATETIME2
	, cloudCover int, dayOrNight char(1), iconCode int, iconCodeExtend int, info varchar(255), precipChance int, precipType varchar(32)
	, qpf0 float, qualifierPhrase varchar(32), relativeHumidity int, air_temperature int, wind_degree float, wind_max_speed int, win_dir_cardinal varchar(3))

insert into @tbl (id) values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15)

update t set t.win_dir_cardinal = LEFT(COALESCE(x.win_dir_cardinal, ''), 3) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS win_dir_cardinal from STRING_SPLIT(@win_dir_cardinal, ','))x ON t.id = x.num

/*
update t set t.moonPhaseDay = x.moonPhaseDay FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS moonPhaseDay from STRING_SPLIT(@moonPhaseDay, ','))x ON t.id = x.num

update t set t.moonPhaseCode = x.moonPhaseCode FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS moonPhaseCode from STRING_SPLIT(@moonPhaseCode, ','))x ON t.id = x.num
	*/
update t set t.narrative = x.narrative FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS narrative from STRING_SPLIT(@narrative, ','))x ON t.id = x.num

update t set t.qpf = (CASE WHEN x.qpf = 'null' THEN 0.0 ELSE CAST(x.qpf AS float) END ) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS qpf from STRING_SPLIT(@qpf, ','))x ON t.id = x.num
	
update t set t.sunriseTimeLocal = convert(datetime2, replace(left(x.sunriseTimeLocal, 19), 'T', ' '), 21) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS sunriseTimeLocal from STRING_SPLIT(@sunriseTimeLocal, ','))x ON t.id = x.num

update t set t.sunsetTimeLocal = convert(datetime2, replace(left(x.sunsetTimeLocal, 19), 'T', ' '), 21) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS sunsetTimeLocal from STRING_SPLIT(@sunsetTimeLocal, ','))x ON t.id = x.num

update t set t.temperatureMax = (CASE WHEN x.temperatureMax = 'null' THEN NULL ELSE x.temperatureMax END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS temperatureMax from STRING_SPLIT(@temperatureMax, ','))x ON t.id = x.num

update t set t.temperatureMin = (CASE WHEN x.temperatureMin = 'null' THEN NULL ELSE x.temperatureMin END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS temperatureMin from STRING_SPLIT(@temperatureMin, ','))x ON t.id = x.num

update t set t.validTimeLocal = convert(datetime2, replace(left(x.validTimeLocal, 19), 'T', ' '), 21) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS validTimeLocal from STRING_SPLIT(@validTimeLocal, ','))x ON t.id = x.num

update t set t.cloudCover = (CASE WHEN x.cloudCover = 'null' THEN NULL ELSE x.cloudCover END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS cloudCover from STRING_SPLIT(@cloudCover, ','))x ON t.id = x.num

update t set t.dayOrNight = (CASE WHEN x.dayOrNight = 'null' THEN NULL ELSE x.dayOrNight END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS dayOrNight from STRING_SPLIT(@dayOrNight, ','))x ON t.id = x.num

update t set t.iconCode = (CASE WHEN x.iconCode = 'null' THEN NULL ELSE x.iconCode END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS iconCode from STRING_SPLIT(@iconCode, ','))x ON t.id = x.num

update t set t.iconCodeExtend = (CASE WHEN x.iconCodeExtend = 'null' THEN NULL ELSE x.iconCodeExtend END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS iconCodeExtend from STRING_SPLIT(@iconCodeExtend, ','))x ON t.id = x.num
	
update t set t.info = (CASE WHEN x.info = 'null' THEN NULL ELSE x.info END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS info from STRING_SPLIT(@info, ','))x ON t.id = x.num
	
update t set t.precipChance = (CASE WHEN x.precipChance = 'null' THEN NULL ELSE x.precipChance END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS precipChance from STRING_SPLIT(@precipChance, ','))x ON t.id = x.num
	
update t set t.precipType = (CASE WHEN x.precipType = 'null' THEN NULL ELSE x.precipType END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS precipType from STRING_SPLIT(@precipType, ','))x ON t.id = x.num
	 
update t set t.qpf0 = (CASE WHEN x.qpf0 = 'null' THEN 0.0 ELSE  CAST(x.qpf0 AS float) END)  FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS qpf0 from STRING_SPLIT(@qpf0, ','))x ON t.id = x.num
		
update t set t.qualifierPhrase = LEFT((CASE WHEN x.qualifierPhrase = 'null' THEN NULL ELSE x.qualifierPhrase END), 24) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS qualifierPhrase from STRING_SPLIT(@qualifierPhrase, ','))x ON t.id = x.num
	 
update t set t.relativeHumidity = (CASE WHEN x.relativeHumidity = 'null' THEN NULL ELSE x.relativeHumidity END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS relativeHumidity from STRING_SPLIT(@relativeHumidity, ','))x ON t.id = x.num
 
update t set t.air_temperature = (CASE WHEN x.air_temperature = 'null' THEN NULL ELSE x.air_temperature END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS air_temperature from STRING_SPLIT(@air_temperature, ','))x ON t.id = x.num
--PrintWindDescription()
update t set t.wind_degree = (CASE WHEN x.wind_degree = 'null' THEN NULL ELSE x.wind_degree END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS wind_degree from STRING_SPLIT(@wind_degree, ','))x ON t.id = x.num

update t set t.wind_max_speed = (CASE WHEN x.wind_max_speed = 'null' THEN NULL ELSE x.wind_max_speed END) FROM @tbl t JOIN 
	(SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) as num, REPLACE(value, '"', '') AS wind_max_speed from STRING_SPLIT(@wind_max_speed, ','))x ON t.id = x.num
	 
update @tbl set temperatureMin = (temperatureMin-32.0)*(5.0/9.0), temperatureMax = (temperatureMax-32.0)*(5.0/9.0), air_temperature = (air_temperature-32)*(5.0/9.0);

DELETE FROM @tbl WHERE validTimeLocal IS NULL
UPDATE @tbl SET temperatureMin = COALESCE(temperatureMin,air_temperature,temperatureMax), temperatureMax = COALESCE(temperatureMax,air_temperature,temperatureMin)
  
	MERGE INTO weather_Forecast AS t
        USING @tbl AS source ON t.dt = CAST(source.validTimeLocal AS DATE ) AND t.mli = @mli  
    WHEN MATCHED THEN 
	UPDATE SET t.tmLow = source.temperatureMin, t.tmHigh = source.temperatureMax, t.rain_today = COALESCE(qpf0, qpf)
	 , t.gpfDay = source.qpf, t.gpfNight = source.qpf0, t.air_temperature = source.air_temperature, t.weather_code = source.iconCode
	 , t.wind_degree = source.wind_degree, t.wind_max_speed = source.wind_max_speed, t.wind_direction = source.win_dir_cardinal, t.shortText = LEFT(source.narrative, 64)
    WHEN NOT MATCHED BY TARGET THEN  
        INSERT ( link,  mli,  dt,                           tm,                           tmLow,          tmHigh,         gpfDay, gpfNight,            air_temperature, weather_code, wind_degree, wind_max_speed , wind_direction ) 
		VALUES ( @link, @mli, CAST(validTimeLocal AS DATE), CAST(validTimeLocal AS TIME), temperatureMin, temperatureMax, qpf,   COALESCE(qpf0, qpf), air_temperature, iconCode    , wind_degree, wind_max_speed ,  win_dir_cardinal  );
  
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     

GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------


/*
	Procedure parse JSON doc and then insert into diffrent tables:
	1. WaterStation - meteo from water station
	2. weather_Forecast

		called from [TR_ows_meteo]
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_ows_meteo_open]
      @js   nvarchar(max)
    , @mli  varchar(64)
    , @link uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        IF @js IS NULL OR @mli IS NULL OR @link IS NULL OR ISJSON(@js) <> 1
            RETURN;

        ;WITH
        hourly_time AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(datetime2(0), REPLACE([value], 'T', ' ')) AS validTimeLocal
            FROM OPENJSON(@js, '$.hourly.time')
        ),
        hourly_temperature AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS air_temperature
            FROM OPENJSON(@js, '$.hourly.temperature_2m')
        ),
        hourly_humidity AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS humidity
            FROM OPENJSON(@js, '$.hourly.relative_humidity_2m')
        ),
        hourly_pop AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(int, [value]) AS pop
            FROM OPENJSON(@js, '$.hourly.precipitation_probability')
        ),
        hourly_pressure AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(int, [value]) AS pressure
            FROM OPENJSON(@js, '$.hourly.pressure_msl')
        ),
        hourly_wind_speed AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS wind_max_speed
            FROM OPENJSON(@js, '$.hourly.wind_speed_10m')
        ),
        hourly_wind_degree AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS wind_degree
            FROM OPENJSON(@js, '$.hourly.wind_direction_10m')
        ),
        hourly_weather_code AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(int, [value]) AS weather_code
            FROM OPENJSON(@js, '$.hourly.weather_code')
        ),
        hourly_rain AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS rain_mm
            FROM OPENJSON(@js, '$.hourly.rain')
        ),
        hourly_data AS
        (
            SELECT
                  t.idx
                , t.validTimeLocal
                , CAST(t.validTimeLocal AS date) AS dt
                , CAST(t.validTimeLocal AS time(7)) AS tm
                , tmp.air_temperature
                , hum.humidity
                , pp.pop
                , prs.pressure
                , ws.wind_max_speed
                , wd.wind_degree
                , wc.weather_code
                , rn.rain_mm
            FROM hourly_time t
            LEFT JOIN hourly_temperature  tmp ON tmp.idx = t.idx
            LEFT JOIN hourly_humidity     hum ON hum.idx = t.idx
            LEFT JOIN hourly_pop          pp  ON pp.idx  = t.idx
            LEFT JOIN hourly_pressure     prs ON prs.idx = t.idx
            LEFT JOIN hourly_wind_speed   ws  ON ws.idx  = t.idx
            LEFT JOIN hourly_wind_degree  wd  ON wd.idx  = t.idx
            LEFT JOIN hourly_weather_code wc  ON wc.idx  = t.idx
            LEFT JOIN hourly_rain         rn  ON rn.idx  = t.idx
            WHERE t.validTimeLocal IS NOT NULL
        ),
        daily_time AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(date, [value]) AS dt
            FROM OPENJSON(@js, '$.daily.time')
        ),
        daily_tmax AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS tmHigh
            FROM OPENJSON(@js, '$.daily.temperature_2m_max')
        ),
        daily_tmin AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(float, [value]) AS tmLow
            FROM OPENJSON(@js, '$.daily.temperature_2m_min')
        ),
        daily_data AS
        (
            SELECT
                  d.dt
                , mx.tmHigh
                , mn.tmLow
            FROM daily_time d
            LEFT JOIN daily_tmax mx ON mx.idx = d.idx
            LEFT JOIN daily_tmin mn ON mn.idx = d.idx
            WHERE d.dt IS NOT NULL
        ),
        rain_by_day AS
        (
            SELECT
                  h.dt
                , SUM(CASE WHEN DATEPART(HOUR, h.validTimeLocal) BETWEEN 6 AND 17
                           THEN ISNULL(h.rain_mm, 0) ELSE 0 END) AS gpfDay
                , SUM(CASE WHEN DATEPART(HOUR, h.validTimeLocal) NOT BETWEEN 6 AND 17
                           THEN ISNULL(h.rain_mm, 0) ELSE 0 END) AS gpfNight
                , SUM(ISNULL(h.rain_mm, 0)) AS rain_today
                , AVG(CASE WHEN DATEPART(HOUR, h.validTimeLocal) BETWEEN 6 AND 17
                           THEN h.air_temperature END) AS tmDay
            FROM hourly_data h
            GROUP BY h.dt
        ),
        src AS
        (
            SELECT
                  @link AS [link]
                , d.tmHigh
                , d.tmLow
                , ISNULL(r.gpfDay, 0.0) AS gpfDay
                , ISNULL(r.gpfNight, 0.0) AS gpfNight
                , h.humidity
                , h.wind_max_speed
                , h.wind_degree
                , CASE
                    WHEN h.wind_degree IS NULL THEN NULL
                    WHEN h.wind_degree >= 337.5 OR h.wind_degree < 22.5 THEN 'N'
                    WHEN h.wind_degree < 67.5  THEN 'NE'
                    WHEN h.wind_degree < 112.5 THEN 'E'
                    WHEN h.wind_degree < 157.5 THEN 'SE'
                    WHEN h.wind_degree < 202.5 THEN 'S'
                    WHEN h.wind_degree < 247.5 THEN 'SW'
                    WHEN h.wind_degree < 292.5 THEN 'W'
                    ELSE 'NW'
                  END AS wind_direction
                , CASE h.weather_code
                    WHEN 0  THEN 'Clear'
                    WHEN 1  THEN 'Mainly clear'
                    WHEN 2  THEN 'Partly cloudy'
                    WHEN 3  THEN 'Overcast'
                    WHEN 45 THEN 'Fog'
                    WHEN 48 THEN 'Rime fog'
                    WHEN 51 THEN 'Light drizzle'
                    WHEN 53 THEN 'Drizzle'
                    WHEN 55 THEN 'Dense drizzle'
                    WHEN 61 THEN 'Light rain'
                    WHEN 63 THEN 'Rain'
                    WHEN 65 THEN 'Heavy rain'
                    WHEN 71 THEN 'Light snow'
                    WHEN 73 THEN 'Snow'
                    WHEN 75 THEN 'Heavy snow'
                    WHEN 80 THEN 'Rain showers'
                    WHEN 81 THEN 'Rain showers'
                    WHEN 82 THEN 'Heavy showers'
                    WHEN 95 THEN 'Thunderstorm'
                    ELSE 'Unknown'
                  END AS shortText
                , CASE h.weather_code
                    WHEN 0  THEN 'Clear sky'
                    WHEN 1  THEN 'Mainly clear sky'
                    WHEN 2  THEN 'Partly cloudy'
                    WHEN 3  THEN 'Overcast'
                    WHEN 45 THEN 'Fog'
                    WHEN 48 THEN 'Depositing rime fog'
                    WHEN 51 THEN 'Light drizzle'
                    WHEN 53 THEN 'Moderate drizzle'
                    WHEN 55 THEN 'Dense drizzle'
                    WHEN 61 THEN 'Slight rain'
                    WHEN 63 THEN 'Moderate rain'
                    WHEN 65 THEN 'Heavy rain'
                    WHEN 71 THEN 'Slight snow fall'
                    WHEN 73 THEN 'Moderate snow fall'
                    WHEN 75 THEN 'Heavy snow fall'
                    WHEN 80 THEN 'Slight rain showers'
                    WHEN 81 THEN 'Moderate rain showers'
                    WHEN 82 THEN 'Violent rain showers'
                    WHEN 95 THEN 'Thunderstorm'
                    ELSE 'Unknown weather condition'
                  END AS longText
                , CONCAT('om_', ISNULL(CONVERT(varchar(12), h.weather_code), 'na'), '.png') AS icon
                , h.pop
                , h.dt
                , h.tm
                , @mli AS mli
                , CAST(NULL AS int) AS city_id
                , h.pressure
                , TRY_CONVERT(int, ROUND(r.rain_today, 0)) AS rain_today
                , TRY_CONVERT(int, ROUND(h.air_temperature, 0)) AS air_temperature
                , r.tmDay
                , h.weather_code
            FROM hourly_data h
            LEFT JOIN daily_data d  ON d.dt = h.dt
            LEFT JOIN rain_by_day r ON r.dt = h.dt
        )

        MERGE dbo.weather_Forecast AS t
        USING src
           ON t.mli = src.mli
          AND t.dt  = src.dt
          AND ISNULL(t.tm, CAST('00:00:00' AS time)) = ISNULL(src.tm, CAST('00:00:00' AS time))

        WHEN MATCHED THEN
            UPDATE SET
                  t.[link]            = src.[link]
                , t.tmHigh            = ISNULL(src.tmHigh, t.tmHigh)
                , t.tmLow             = ISNULL(src.tmLow, t.tmLow)
                , t.gpfDay            = src.gpfDay
                , t.gpfNight          = src.gpfNight
                , t.humidity          = src.humidity
                , t.wind_max_speed    = src.wind_max_speed
                , t.wind_degree       = src.wind_degree
                , t.wind_direction    = src.wind_direction
                , t.shortText         = LEFT(src.shortText, 64)
                , t.longText          = LEFT(src.longText, 255)
                , t.icon              = LEFT(src.icon, 255)
                , t.pop               = src.pop
                , t.pressure          = src.pressure
                , t.rain_today        = src.rain_today
                , t.air_temperature   = src.air_temperature
                , t.tmDay             = src.tmDay
                , t.weather_code      = src.weather_code

        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                  [link]
                , [tmHigh]
                , [tmLow]
                , [gpfDay]
                , [gpfNight]
                , [humidity]
                , [wind_max_speed]
                , [wind_degree]
                , [wind_direction]
                , [shortText]
                , [longText]
                , [icon]
                , [pop]
                , [dt]
                , [tm]
                , [mli]
                , [city_id]
                , [pressure]
                , [rain_today]
                , [air_temperature]
                , [tmDay]
                , [weather_code]
            )
            VALUES
            (
                  src.[link]
                , ISNULL(src.tmHigh, 0)
                , ISNULL(src.tmLow, 0)
                , ISNULL(src.gpfDay, 0)
                , ISNULL(src.gpfNight, 0)
                , src.humidity
                , src.wind_max_speed
                , src.wind_degree
                , src.wind_direction
                , LEFT(src.shortText, 64)
                , LEFT(src.longText, 255)
                , LEFT(src.icon, 255)
                , src.pop
                , src.dt
                , src.tm
                , src.mli
                , src.city_id
                , src.pressure
                , src.rain_today
                , src.air_temperature
                , src.tmDay
                , src.weather_code
            );

    END TRY
    BEGIN CATCH
        SELECT
              ERROR_NUMBER()    AS ErrorNumber
            , ERROR_SEVERITY()  AS ErrorSeverity
            , ERROR_STATE()     AS ErrorState
            , ERROR_PROCEDURE() AS ErrorProcedure
            , ERROR_LINE()      AS ErrorLine
            , ERROR_MESSAGE()   AS ErrorMessage;
    END CATCH
END
GO


------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_save_lake_state' AND type = 'P')
    DROP PROCEDURE dbo.sp_save_lake_state
GO

/*
	save river state to database

	declare @data xml = N'<root PH="4" TDS="3.4"/>';
	EXEC sp_save_lake_state @data,  '743a5733-bf0d-11d8-92e2-080020a0f4c9', 4
	SELECT * FROM Lake_State WHERE lake_id = '743a5733-bf0d-11d8-92e2-080020a0f4c9'
*/
 
CREATE PROCEDURE dbo.sp_save_lake_state @data xml, @lake_id uniqueidentifier,  @month int
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
  IF NOT EXISTS (SELECT * FROM Lake_State WHERE Lake_id = @lake_id AND [month] = @month)
  BEGIN   -- get latest changed month
	INSERT INTO Lake_State (PH, phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium
		, Chloride, Bicarbonate, Transparency, Oxygen, Salinity, Clarity, Velocity, water_degree, air_degree
		, [month], lake_id )
		SELECT TOP 1 PH, phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium
		, Chloride, Bicarbonate, Transparency, Oxygen, Salinity, Clarity, Velocity, water_degree, air_degree
		, @month, lake_id FROM Lake_State
			WHERE lake_id = @lake_id ORDER BY stamp DESC

	IF NOT EXISTS (SELECT * FROM Lake_State WHERE Lake_id = @lake_id AND [month] = @month)
		INSERT INTO Lake_State ( [month], lake_id) VALUES (@month, @lake_id)
  END;

  ;WITH cte AS
  (
	SELECT  X.C.value(N'@PH', N'float')      as ph
	 , X.C.value(N'@phosphorus', N'float')   as phosphorus
	 , X.C.value(N'@TDS', N'float')          as tds
	 , X.C.value(N'@Conductivity', N'float') as Conductivity
	 , X.C.value(N'@Alkalinity', N'float')   as Alkalinity
	 , X.C.value(N'@Hardness', N'float')     as Hardness
	 , X.C.value(N'@Sodium', N'float')       as Sodium
	 , X.C.value(N'@Chloride', N'float')     as Chloride
	 , X.C.value(N'@Bicarbonate', N'float')  as Bicarbonate
	 , X.C.value(N'@Transparency', N'float') as Transparency
	 , X.C.value(N'@Oxygen', N'float')       as Oxygen
	 , X.C.value(N'@Salinity', N'float')     as Salinity
	 , X.C.value(N'@Clarity', N'float')      as Clarity
	 , X.C.value(N'@Velocity', N'float')     as Velocity
	 , X.C.value(N'@water_degree', N'float') as water_degree
	 , X.C.value(N'@air_degree', N'float')   as air_degree
	 , X.C.value(N'@cold_cool', N'bit')      as cold_cool
	 , X.C.value(N'@flow_stand', N'bit')     as flow_stand
	  FROM (SELECT @data AS XML_DATA) DATA CROSS APPLY DATA.XML_DATA.nodes(N'/root') as X(C)
  )update l SET l.ph = cte.ph,           l.phosphorus  = cte.phosphorus 
	, l.Conductivity = cte.Conductivity, l.Alkalinity  = cte.Alkalinity 
	, l.Hardness     = cte.Hardness ,    l.Sodium      = cte.Sodium 
	, l.Chloride     = cte.Chloride  ,   l.Bicarbonate = cte.Bicarbonate 
	, l.Transparency = cte.Transparency, l.Oxygen      = cte.Oxygen 
	, l.Salinity     = cte.Salinity  ,   l.Clarity     = cte.Clarity 
	, l.Velocity     = cte.Velocity ,    l.tds         = cte.tds
	, l.water_degree = cte.water_degree, l.air_degree  = cte.air_degree
	, l.flow_stand = cte.flow_stand,     l.cold_cool  = cte.cold_cool
  FROM cte JOIN Lake_State l ON l.lake_id = @lake_id AND l.month = @month

  RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     

GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spUpdateFishFood' AND type = 'P')
    DROP PROCEDURE dbo.spUpdateFishFood
GO


CREATE PROCEDURE dbo.spUpdateFishFood @fish_id uniqueidentifier
   , @food_habitat int, @locked bit, @editor uniqueidentifier
   , @terrestrial_insects int
   , @terrestrial_animals int
   , @crustaceans int
   , @node_food_habitat nvarchar(max)
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
	UPDATE dbo.fish Set stamp = GETUTCDATE(), locked = @locked, editor=@editor 
	  , food_habitat=@food_habitat, terrestrial_insects=@terrestrial_insects
	  , terrestrial_animals=@terrestrial_animals, crustaceans=@crustaceans
	  , node_food_habitat = @node_food_habitat
	  WHERE fish_id =  @fish_Id;

  RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spUpdateFishPredator' AND type = 'P')
    DROP PROCEDURE dbo.spUpdateFishPredator
GO

/*
		Add fish as a food for predator

		EXEC  dbo.spUpdateFishPredator '2cffb500-3e59-4120-9460-055856e9ac5c', 'dc38e981-2a0e-4f55-9179-6c6f9619cf0b'
*/

CREATE PROCEDURE dbo.spUpdateFishPredator @fish_id uniqueidentifier, @predator_id uniqueidentifier
WITH EXEC AS CALLER
AS 
BEGIN TRY  
SET NOCOUNT ON;
    IF @fish_id = @predator_id
		RETURN;
	If NOT EXISTS (SELECT * FROM fish_predator WHERE fish_id = @fish_id AND @predator_id = predator_id)
		INSERT INTO fish_predator (fish_id, predator_id) VALUES (@fish_id, @predator_id);

  RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO


------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_AddCaWaterData' AND type = 'P')
    DROP PROCEDURE dbo.sp_AddCaWaterData
GO
/*
	WaterWorkerService service call procedure to update canadian water data 

    declare @jsondoc nvarchar(max) = N'[{\"dt\":\"2021-01-27T00:00:00-05:00\",\"wl\":8.85,\"ds\":2.399},{\"dt\":\"2021-01-28T18:00:00-05:00\",\"wl\":7.19,\"ds\":2.339}]';
	EXEC  sp_AddCaWaterData '02CA007', 'ON', @jsondoc, 1.0

	select * from WaterData where mli='02CA007' and CAST(stamp AS DATE) >= '20200127' order by stamp desc

	delete from WaterData where mli='02CA007' and CAST(stamp AS DATE) >= '20200127'
*/

CREATE PROCEDURE sp_AddCaWaterData @mli varchar(64), @state nvarchar(8),  @jsondoc nvarchar(max), @koef float
AS
SET NOCOUNT ON
BEGIN TRY
    IF @jsondoc IS NULL
		RETURN
	declare @val nvarchar(max) = replace(@jsondoc, N'\"', N'"');
	
;WITH cte( discharge, elevation, dt)  AS
(
	SELECT AVG(ds), AVG(wl), CAST(dt AS DATE) FROM 
	(
		SELECT ds, wl, CONVERT(datetime, replace(LEFT(dt, 19), N'T', N' '), 120) AS dt 
			FROM OPENJSON(@val) WITH (dt varchar(32), wl float, ds float) 
	)x  GROUP BY CAST(dt AS DATE)
)
MERGE INTO WaterData AS t
        USING cte AS source ON CAST(t.stamp AS DATE ) = source.dt AND t.mli = @mli
    WHEN MATCHED THEN 
        UPDATE SET t.discharge = COALESCE(source.discharge * @koef,   t.discharge)
				 , t.elevation = COALESCE(source.elevation * @koef,   t.elevation)
    WHEN NOT MATCHED BY TARGET THEN  
        INSERT (stamp, discharge, elevation, mli ) 
		VALUES ( dt,  discharge,  elevation, @mli );

	RETURN @@ROWCOUNT
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spClear' AND type = 'P')
    DROP PROCEDURE dbo.spClear
GO
CREATE PROCEDURE dbo.spClear
AS
SET NOCOUNT ON
	BEGIN TRY 
	-- clear [SessionHandler]
	  ;WITH RankedSessions AS (
		SELECT
			id,
			ROW_NUMBER() OVER(PARTITION BY host, CAST(startSess AS DATE) ORDER BY startSess ASC) AS rn
		FROM
			[dbo].[SessionHandler]
	)
	DELETE FROM [dbo].[SessionHandler]
	WHERE id IN (
		SELECT id FROM RankedSessions WHERE rn > 1
	);
	SELECT @@ROWCOUNT
	--
	 delete from [dbo].[WaterData] where stamp < CAST(DATEADD(day, -15, GETDATE()) AS DATE);
	 SELECT @@ROWCOUNT
   --
	 delete from [dbo].[weather_Forecast]  where dt < CAST(DATEADD(day, -15, GETDATE()) AS DATE);
	 SELECT @@ROWCOUNT
 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- used in water data services
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_DisableWaterStation' AND type = 'P')
    DROP PROCEDURE dbo.sp_DisableWaterStation
GO

CREATE OR ALTER PROCEDURE dbo.sp_DisableWaterStation
    @mli varchar(64)
AS
SET NOCOUNT ON
BEGIN TRY 

    UPDATE dbo.WaterStation SET supported = 0 WHERE mli = @mli;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH

GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_UpdateWaterData' AND type = 'P')
    DROP PROCEDURE dbo.sp_UpdateWaterData
GO

CREATE OR ALTER PROCEDURE dbo.sp_UpdateWaterData
    @mli varchar(64),
    @stamp datetime2,
    @elevation float,
    @discharge float
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.WaterData
    SET elevation = @elevation,
        discharge = @discharge
    WHERE mli = @mli
      AND stamp = @stamp;

    IF @@ROWCOUNT = 0
    BEGIN
        BEGIN TRY
            INSERT INTO dbo.WaterData (mli, stamp, elevation, discharge)
            VALUES (@mli, @stamp, @elevation, @discharge);
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() IN (2601, 2627)
            BEGIN
                UPDATE dbo.WaterData
                SET elevation = @elevation,
                    discharge = @discharge
                WHERE mli = @mli
                  AND stamp = @stamp;
            END
            ELSE
            BEGIN
                THROW;
            END
        END CATCH
    END
END;
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
