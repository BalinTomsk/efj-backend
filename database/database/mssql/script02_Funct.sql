-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_clean_river_name')
    DROP FUNCTION dbo.fn_clean_river_name
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_list' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_river_list
GO

/*
    Usage:
        SELECT dbo.fn_clean_river_name( N'Chumak Viteetshìk' )
*/

CREATE FUNCTION dbo.fn_clean_river_name( @full_river_name sysname )
RETURNS sysname
WITH SCHEMABINDING 
BEGIN
	DECLARE @result sysname = @full_river_name
	SELECT TOP 1 @result = CASE WHEN NULLIF(val, '') IS NULL THEN @full_river_name ELSE val END FROM 
		(
			SELECT DISTINCT z.val FROM 
			(
				SELECT DISTINCT val FROM 
				( 
					SELECT CAST(en AS sysname) As name FROM dbo.water_body 
					UNION ALL
					SELECT fr FROM dbo.water_body 
					UNION ALL
					SELECT gw FROM dbo.water_body WHERE gw IS NOT NULL
				) l CROSS APPLY 
					(SELECT TRIM(REPLACE(@full_river_name, l.name, N'')) )x(val)
			)z
		)y WHERE y.val <> @full_river_name
	RETURN @result
END
GO

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStationInfo' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStationInfo
GO

CREATE FUNCTION dbo.GetStationInfo( @fishId uniqueidentifier, @placeId bigint )
  RETURNS @TBL TABLE (wheatherStamp datetime, lat float, lon float, loadWeather int
        , county varchar(64), city varchar(64), state char(2), country char(2), locName varchar(max), id uniqueidentifier
        , today int
        , temperature float, turbidity float, oxygen float, sid int, mli varchar(64)
        , stamp datetime, discharge float, elevation float )
    AS
    begin
      DECLARE @today int, @temperature float, @turbidity float, @oxygen float, @state char(2)
      DECLARE @stamp datetime, @discharge float, @elevation float, @locId uniqueidentifier, @shift int
      DECLARE @isw int, @wsId uniqueidentifier, @mli varchar(64)
      
      SELECT @mli = w.mli, @wsId = w.id, @today = f.today  FROM WaterStation w 
        JOIN dbo.fish_location f ON  (w.id = f.station_Id) WHERE w.sid=@placeId and @fishId = fish_Id
    
  INSERT INTO @TBL   
    SELECT w.wheatherStamp, w.lat, w.lon, 0 as loadWeather, county, city, [state], country, locName, id, @today 
       , s.temperature, s.turbidity, s.oxygen, w.sid, w.mli, s.stamp, s.discharge, s.elevation
    FROM vWaterStation w, CurrentWaterState s  WHERE w.mli=s.mli AND w.sid = @placeId
    
    SELECT @stamp = stamp, @state = state FROM @TBL  
    SELECT @shift = shift FROM states WHERE state = @state
    SET @stamp = DATEADD( HOUR, -@shift, @stamp)
    SELECT @isw = COUNT(*) FROM dbo.weather_Forecast   -- check if todays weather is saved
       WHERE link= @wsId AND CONVERT(VARCHAR(10),GETDATE(),101) <= dt AND tm IS NULL
    UPDATE @TBL SET stamp = @stamp, loadWeather = ISNULL(@isw, 0)         
  return
END      
GO
----------  display current wheather for last 10 days from ForecastFrame.aspx.cs ----------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fnWeatherForecast' AND xtype = 'TF')
    DROP FUNCTION dbo.fnWeatherForecast
GO

CREATE FUNCTION dbo.fnWeatherForecast( @link uniqueidentifier )
  RETURNS @TBL TABLE (dt date, wind_degree float, gpfDay float, gpfNight float, humidity int
  , wind_direction varchar(4), tmLow float, tmHigh float, wind_max_speed float, shortText varchar(255)
  , longText  varchar(255), icon  varchar(32)  )
AS
BEGIN
  INSERT INTO @TBL
    SELECT dt, wind_degree, gpfDay, gpfNight, humidity, wind_direction
    , tmLow, tmHigh, wind_max_speed, shortText, longText, icon
      FROM weather_Forecast WHERE tm IS NULL AND dt >= CONVERT(VARCHAR(10),GETDATE(),101)   
        AND link = @link 
  RETURN
END  
GO  
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_fish_list_type' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_fish_list_type
GO
/*
    Used in Admin -> FishList
    select * from dbo.fn_get_fish_list_type( 1 ) ORDER BY fish_name ASC 
----------  get list of species for editing ----------------
*/
--  select * from dbo.fn_get_fish_list_type( 32 )   -- sport fishes
-- 1 - sport, 2 - commersial, 4 - invading
CREATE FUNCTION fn_get_fish_list_type( @fish_type int )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
SELECT ROW_NUMBER() OVER (ORDER BY fish_name ASC) AS num, fish_name, fish_latin, fish_id FROM
(
      SELECT fish_name, fish_latin, fish_id, 0 AS line FROM dbo.fish
      UNION ALL
      SELECT fish_name, fish_latin, fish_id, 1 AS line FROM dbo.fish 
        WHERE @fish_type = @fish_type & fish_type
)a WHERE line = CASE WHEN @fish_type IS NULL OR 0 = @fish_type THEN 0 ELSE 1 END
 GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_location' AND xtype = 'IF')
    DROP function dbo.fn_get_trial_location
GO

CREATE function [dbo].fn_get_trial_location( @fishName  varchar(64), @lat float, @lon float )
  RETURNS  TABLE
  WITH SCHEMABINDING
AS
RETURN
    SELECT w.mli, w.county, w.state, w.country, w.LocName as location, w.sid, w.lat, w.lon, f.today 
      FROM dbo.vWaterStation w JOIN [dbo].[fish_location] f ON (f.station_Id = w.id  )
      WHERE ( w.lat between (@lat-1.0) AND (@lat+1.0) ) AND (w.lon between (@lon-1.0) AND (@lon+1.0) ) 
        AND EXISTS( SELECT fish_name FROM dbo.fish s WHERE fish_name = @fishName and f.fish_id = s.fish_id )
GO
-- select * from [dbo].fn_get_trial_location( 'Burbot', 43, -80 )
-------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetUserLocation' AND xtype = 'TF')
    DROP FUNCTION dbo.GetUserLocation
GO

create function dbo.GetUserLocation( @userId uniqueidentifier )
  RETURNS @TBL TABLE ( postal sysname, lat float, lon float, email sysname )
    AS
BEGIN
  DECLARE @postal sysname, @email sysname    
  SELECT TOP 1 @postal=postal, @email=email FROM users WHERE id=@userId
--  IF 0 > LEN(@postal)
--    RETURN;
  INSERT INTO @TBL   
  select TOP 1 @postal, lat, lon, @email from dbo.GetLatLonByPostal( @postal )
  RETURN;
END
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_fish_bylatlon
GO

CREATE FUNCTION dbo.fn_get_fish_bylatlon( @lat real, @lon real, @dist real  )
  RETURNS TABLE 
RETURN
  SELECT DISTINCT fish_id, fish_name FROM 
  (
    SELECT fish_id, fish_name FROM dbo.vget_fish_list v
      WHERE EXISTS
        ( SELECT * FROM dbo.fish_location f JOIN WaterStation w ON (f.station_Id = w.id)
            WHERE f.fish_id = v.fish_id 
           AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
           AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
           AND w.country = 'US'
        )      
    UNION ALL
    SELECT s.fish_id, v.fish_name FROM dbo.vget_fish_list v RIGHT JOIN Fish_State s ON (v.fish_id = s.fish_id)
      WHERE EXISTS
        ( SELECT * FROM dbo.fish_location f JOIN WaterStation w ON (f.station_Id = w.id)
            WHERE f.fish_id = v.fish_id 
           AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
           AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
           AND w.country = 'CA'
        )     
   )ul 
GO
--  SELECT * FROM dbo.GetLatLonByIP( '::1' )
-- select * from dbo.fn_get_fish_bylatlon( 41, -83, 3 )    -- V5K 0A1
----------------------------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByPostal' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLatLonByPostal
GO

CREATE FUNCTION GetLatLonByPostal( @postal varchar(8) )
RETURNS @TBL TABLE (lat float, lon float )
AS
begin
  IF 1 = ISNUMERIC(@postal) AND (LEN(@postal) = 5 OR LEN(@postal) = 4)
  BEGIN
    insert into @TBL
      SELECT lat, lon FROM [USPost] where  zip= @postal 
  END
  ELSE
    insert into @TBL SELECT lat, lon  FROM CanPostLatLon  where postal=@postal
  return
end          
GO     
-- SELECT TOP 1 lat, lon FROM dbo.GetLatLonByPostal( 'V2K1G7' )
-- SELECT TOP 1 lat, lon FROM dbo.GetLatLonByPostal( '98101' )
 
----------------------------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByIP' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLatLonByIP
GO

CREATE FUNCTION GetLatLonByIP( @ip sysname )
RETURNS @TBL TABLE (lat float, lon float )
AS
begin
  declare @ip4 binary(4)
  SET @ip4 = CAST( dbo.IP2Int(@ip) AS binary(4) )
  if EXISTS (SELECT * FROM dbo.GeoIP WHERE ip4 = @ip4)
      insert into @TBL SELECT latitude, longitude FROM GeoIP WHERE ip4 = @ip4
  ELSE
    insert into @TBL (lat , lon ) VALUES (41, -80)
  return
end         
GO

--  select * from dbo.GetLatLonByIP( '38.127.167.46' )

----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'CheckInterval' AND xtype = 'FN')
    DROP FUNCTION dbo.CheckInterval
GO    

create function dbo.CheckInterval( @low float, @high float  )
RETURNS BIT
AS
BEGIN
  DECLARE @rst BIT
  SET @rst = 0;
  IF @low IS NOT NULL AND @high IS NOT NULL AND @high > @low 
    SET @rst = 1;
  RETURN @rst;        
END
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStation' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStation
GO

create function dbo.GetStation( @lat float, @lon float, @dist float )
  RETURNS @TBL TABLE (mli varchar(32) NOT NULL PRIMARY KEY, lat float, lon float )
    AS
    begin
      insert into @TBL (mli, lat, lon)
         SELECT mli, lat, lon FROM vWaterStation w
              WHERE ( lat between (@lat-@dist) AND (@lat+@dist) ) AND (lon between (@lon-@dist) AND (@lon+@dist) ) 
                AND EXISTS ( select * from dbo.fish_location f WHERE f.station_Id = w.id )
  return
END      
GO
--  SELECT mli, lat, lon FROM dbo.GetStation( 40, -81, 3 ) 
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'Int2IP' AND xtype = 'FN')
    DROP function dbo.Int2IP
GO

CREATE function dbo.Int2IP
(@i bigint)
returns varchar(15)
WITH SCHEMABINDING
as
begin
  return        cast((@i/16777216)%256 as varchar(3)) 
    +'.'+cast((@i/65536)%256 as varchar(3))
    +'.'+cast((@i/256)%256 as varchar(3))
    +'.'+cast(@i%256 as varchar(3))
end
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'BinaryToIP' AND xtype = 'FN')
    DROP FUNCTION dbo.BinaryToIP
GO

CREATE  FUNCTION dbo.BinaryToIP
    (
    @binIP Binary(4)
    )
RETURNS varchar(15)
WITH SCHEMABINDING
AS
    BEGIN
        DECLARE @Tmp bigint
        SET @Tmp=@binIP
RETURN  LTRIM(STR((@Tmp & 0xff000000) /0x1000000))+'.'+
    LTRIM(STR((@Tmp & 0xff0000) /0x10000))+'.'+
    LTRIM(STR((@Tmp & 0xff00) /0x100))+'.'+
    LTRIM(STR((@Tmp & 0xff)))

    END
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'IpToBinary' AND xtype = 'FN')
    DROP FUNCTION dbo.IpToBinary
GO

CREATE  FUNCTION dbo.IpToBinary( @strIP varchar(15) )
  RETURNS Binary(4)
WITH SCHEMABINDING
AS
    BEGIN
        DECLARE @Tmp Binary(4)
        SET @Tmp=CAST(
        CAST(PARSENAME(@strIP,4) as bigint)*0x1000000
        +CAST(PARSENAME(@strIP,3) as bigint)*0x10000
        +CAST(PARSENAME(@strIP,2) as bigint)*0x100
        +CAST(PARSENAME(@strIP,1) as bigint)
        as binary(4))
        RETURN @Tmp
    END
 GO
----------------------------------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLocations' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLocations
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStation' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStation
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetFisNamePlaceDescr' AND xtype = 'TF')
    DROP FUNCTION dbo.GetFisNamePlaceDescr
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_bylatlon
GO

--  SELECT * FROM dbo.fn_get_trial_fish_bylatlon( 43, -80  ) ORDER BY 2
-------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_bylatlon
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_latlon_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_latlon_byzip
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_location' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_location
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStationInfo' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStationInfo
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStationInfo' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStationInfo
GO

CREATE FUNCTION dbo.GetStationInfo( @fishId uniqueidentifier, @placeId bigint )
  RETURNS @TBL TABLE (wheatherStamp datetime, lat float, lon float, loadWeather int
        , county varchar(64), city varchar(64), state char(2), country char(2), locName varchar(max), id uniqueidentifier
        , today int
        , temperature float, turbidity float, oxygen float, sid int, mli varchar(64)
        , stamp datetime, discharge float, elevation float )
WITH SCHEMABINDING
    AS
    begin
      DECLARE @today int, @temperature float, @turbidity float, @oxygen float, @state char(2)
      DECLARE @stamp datetime, @discharge float, @elevation float, @locId uniqueidentifier, @shift int
      DECLARE @isw int, @wsId uniqueidentifier, @mli varchar(64)
      
      SELECT @mli = w.mli, @wsId = w.id, @today = f.today  FROM dbo.WaterStation w 
        JOIN dbo.fish_location f ON  (w.id = f.station_Id) WHERE w.sid=@placeId and @fishId = fish_Id
    
  INSERT INTO @TBL   
    SELECT w.wheatherStamp, w.lat, w.lon, 0 as loadWeather, county, city, [state], country, locName, id, @today 
       , s.temperature, s.turbidity, s.oxygen, w.sid, w.mli, s.stamp, s.discharge, s.elevation
    FROM dbo.vWaterStation w, dbo.CurrentWaterState s  WHERE w.mli=s.mli AND w.sid = @placeId
    
    SELECT @stamp = stamp, @state = state FROM @TBL  
    SELECT @shift = shift FROM dbo.states WHERE state = @state
    SET @stamp = DATEADD( HOUR, -@shift, @stamp)
    SELECT @isw = COUNT(*) FROM dbo.weather_Forecast   -- check if todays weather is saved
       WHERE link= @wsId AND CONVERT(VARCHAR(10),GETDATE(),101) <= dt AND tm IS NULL
    UPDATE @TBL SET stamp = @stamp, loadWeather = ISNULL(@isw, 0)         
  return
END      
GO

-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_location' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_location
GO

CREATE function dbo.fn_get_trial_location( @fishName  varchar(64), @lat float, @lon float )
  RETURNS  TABLE
  WITH SCHEMABINDING
AS
RETURN
    SELECT w.mli, w.county, w.state, w.country, w.LocName as location, w.sid, w.lat, w.lon, f.today 
      FROM dbo.vWaterStation w JOIN [dbo].[fish_location] f ON (f.station_Id = w.id  )
      WHERE ( w.lat between (@lat-1.0) AND (@lat+1.0) ) AND (w.lon between (@lon-1.0) AND (@lon+1.0) ) 
        AND EXISTS( SELECT fish_name FROM dbo.fish s WHERE fish_name = @fishName and f.fish_id = s.fish_id )
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_bylatlon
GO

CREATE FUNCTION dbo.fn_get_trial_fish_bylatlon( @lat real, @lon real )
  RETURNS TABLE 
WITH SCHEMABINDING
RETURN
    SELECT fish_id, fish_name FROM dbo.vget_trial_fish_list v
      WHERE EXISTS
        ( SELECT TOP 1 1 FROM  dbo.lake_fish  lf
            JOIN dbo.WaterStation w  ON (lf.lake_Id = w.lakeId)
            WHERE ( lf.fish_id = v.fish_Id)
           AND ( w.lat between (@lat-1) AND (@lat+1) )
           AND ( w.lon between (@lon-1) AND (@lon+1) )
        )        
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_bylatlon
GO

CREATE FUNCTION dbo.fn_get_trial_fish_bylatlon( @lat real, @lon real )
  RETURNS TABLE 
WITH SCHEMABINDING
RETURN
    SELECT fish_id, fish_name FROM dbo.vget_trial_fish_list v
      WHERE EXISTS
        ( SELECT TOP 1 1 FROM  dbo.lake_fish  lf
            JOIN dbo.WaterStation w  ON (lf.lake_Id = w.lakeId)
            WHERE ( lf.fish_id = v.fish_Id)
           AND ( w.lat between (@lat-1) AND (@lat+1) )
           AND ( w.lon between (@lon-1) AND (@lon+1) )
        )        
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_latlon_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_latlon_byzip
GO

CREATE FUNCTION dbo.fn_get_latlon_byzip( @zip varchar(6) )
RETURNS  TABLE 
WITH SCHEMABINDING
  RETURN
    SELECT lat, lon FROM 
    (
        SELECT lat, lon, 0 AS country FROM dbo.CanPostLatLon WHERE @zip = postal
        UNION ALL
        SELECT lat, lon, 1 AS country FROM dbo.USPost WHERE @zip = zip
     )a WHERE country = ISNUMERIC(@zip) 
GO
---------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetTrialFishByPostal' AND xtype = 'IF')
    DROP FUNCTION dbo.GetTrialFishByPostal
GO

CREATE FUNCTION dbo.GetTrialFishByPostal( @postal varchar(6) )
RETURNS  TABLE 
  RETURN
    SELECT fish_Id, fish_name, 0 AS country FROM dbo.fn_get_latlon_byzip(@postal) c 
      CROSS APPLY dbo.fn_get_trial_fish_bylatlon( c.lat, c.lon ) l 
GO
--  select * from dbo.GetTrialFishByPostal( 'N2M5L4' )
-------------------------------------------------------------------------------------------------------
CREATE FUNCTION dbo.fn_get_trial_fish_byzip( @postal varchar(6) )
RETURNS  TABLE 
WITH SCHEMABINDING
  RETURN
    SELECT fish_Id, fish_name, 0 AS country FROM dbo.fn_get_latlon_byzip( @postal) c 
      CROSS APPLY dbo.fn_get_trial_fish_bylatlon( c.lat, c.lon  ) l 
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO
--  SELECT * FROM dbo.fn_get_trial_fish_bylatlon( 43, -80  ) ORDER BY 2

CREATE FUNCTION dbo.fn_get_trial_fish_byzip( @postal varchar(6) )
RETURNS  TABLE 
WITH SCHEMABINDING
  RETURN
    SELECT fish_Id, fish_name, 0 AS country FROM dbo.fn_get_latlon_byzip(@postal) c 
      CROSS APPLY dbo.fn_get_trial_fish_bylatlon( c.lat, c.lon  ) l 
GO
----------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetFisNamePlaceDescr' AND xtype = 'TF')
    DROP FUNCTION dbo.GetFisNamePlaceDescr
GO

CREATE function dbo.GetFisNamePlaceDescr( @fishId uniqueidentifier, @placeId bigint  )
  RETURNS @TBL TABLE ( name sysname, place sysname )
WITH SCHEMABINDING
    AS
BEGIN
  DECLARE @place sysname, @desc sysname, @state sysname
  SELECT TOP 1 @place=locName FROM dbo.vWaterStation WHERE sid=@placeId
  INSERT INTO @TBL   
     SELECT TOP 1 fish_name, @place FROM dbo.fish WHERE fish_id=@fishId
  RETURN;
END
GO
----------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStation' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStation
GO

CREATE function dbo.GetStation( @lat float, @lon float, @dist float )
  RETURNS @TBL TABLE (mli varchar(32) NOT NULL PRIMARY KEY, lat float, lon float )
WITH SCHEMABINDING
    AS
    begin
      insert into @TBL (mli, lat, lon)
         SELECT mli, lat, lon FROM dbo.vWaterStation w
              WHERE ( lat between (@lat-@dist) AND (@lat+@dist) ) AND (lon between (@lon-@dist) AND (@lon+@dist) ) 
                AND EXISTS ( select TOP 1 1 from dbo.fish_location f WHERE f.station_Id = w.id )
  return
END      
GO
----------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLocations' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLocations
GO

CREATE function dbo.GetLocations( @fishName  varchar(64), @lat float, @lon float, @dist float )
  RETURNS @TBL TABLE ( mli varchar(32) primary key, county varchar(64), state char(2), country char(2)
                     , name varchar(64), sid int not null, lat float, lon float, today int)
WITH SCHEMABINDING
    AS
BEGIN
  DECLARE @fishId uniqueidentifier
  select @fishId = fish_Id FROM dbo.fish WHERE fish_name LIKE @fishName

  INSERT INTO @TBL
     SELECT w.mli, w.county, w.state, w.country, w.LocName as name, w.sid, w.lat, w.lon, f.today 
        FROM dbo.vWaterStation w, [dbo].[fish_location] f 
        WHERE ( w.lat between (@lat-@dist) AND (@lat+@dist) ) AND (w.lon between (@lon-@dist) AND (@lon+@dist) ) 
           AND f.station_Id = w.id AND @fishId=f.fish_Id 

   IF EXISTS( SELECT TOP 1 1 FROM @TBL WHERE country = 'CA' AND state = 'ON' )
     DELETE FROM @tbl WHERE country = 'CA' AND state = 'ON' 
       AND mli NOT IN (SELECT w.mli FROM dbo.WaterStation w, dbo.fish_location l 
         WHERE w.Id=l.station_Id AND l.fish_Id = @fishId 
         AND w.country = 'CA' AND w.state = 'ON')

    return
END
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_fish_bylatlon
GO

CREATE FUNCTION dbo.fn_get_fish_bylatlon( @lat real, @lon real, @dist real  )
  RETURNS TABLE 
WITH SCHEMABINDING
RETURN
  SELECT DISTINCT fish_id, fish_name FROM 
  (
    SELECT fish_id, fish_name FROM dbo.vget_fish_list v
      WHERE EXISTS
        ( SELECT TOP 1 1 FROM dbo.fish_location f JOIN dbo.WaterStation w ON (f.station_Id = w.id)
            WHERE f.fish_id = v.fish_id 
           AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
           AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
           AND w.country = 'US'
        )      
    UNION ALL
    SELECT s.fish_id, v.fish_name FROM dbo.vget_fish_list v RIGHT JOIN dbo.Fish_State s ON (v.fish_id = s.fish_id)
      WHERE EXISTS
        ( SELECT TOP 1 1 FROM dbo.fish_location f JOIN dbo.WaterStation w ON (f.station_Id = w.id)
            WHERE f.fish_id = v.fish_id 
           AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
           AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
           AND w.country = 'CA'
        )     
   )ul 
GO
--  SELECT * FROM dbo.GetLatLonByIP( '::1' )
-- select * from dbo.fn_get_fish_bylatlon( 41, -83, 3 )    -- V5K 0A1
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO

create FUNCTION dbo.fn_get_trial_fish_byzip( @postal varchar(6) )
RETURNS  TABLE 
WITH SCHEMABINDING
  RETURN
    SELECT fish_Id, fish_name, 0 AS country FROM dbo.fn_get_latlon_byzip(@postal) c 
      CROSS APPLY dbo.fn_get_trial_fish_bylatlon( c.lat, c.lon  ) l 
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetTrialFishByPostal' AND xtype = 'IF')
    DROP FUNCTION dbo.GetTrialFishByPostal
GO

CREATE FUNCTION dbo.GetTrialFishByPostal( @postal varchar(6) )
RETURNS  TABLE 
  RETURN
    SELECT fish_Id, fish_name, 0 AS country FROM dbo.fn_get_latlon_byzip(@postal) c 
      CROSS APPLY dbo.fn_get_trial_fish_bylatlon( c.lat, c.lon ) l 
GO
--  select * from dbo.GetTrialFishByPostal( 'N2M5L4' )
---------------------------------------------------------------------------------------------
----------  get list of species for editing ----------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_fish_list_type' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_fish_list_type
GO

-- 1 - sport, 2 - commersial, 4 - invading
CREATE FUNCTION fn_get_fish_list_type( @fish_type int )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
SELECT ROW_NUMBER() OVER (ORDER BY fish_name ASC) AS num, fish_name, fish_latin, fish_id FROM
(
  SELECT fish_name, fish_latin, fish_id, 0 AS line FROM dbo.fish
  UNION ALL
  SELECT fish_name, fish_latin, fish_id, 1 AS line FROM dbo.fish 
    WHERE @fish_type = @fish_type & fish_type
 )a WHERE line = CASE WHEN @fish_type IS NULL OR 0 = @fish_type THEN 0 ELSE 1 END
GO
 --  select * from dbo.fn_get_fish_list_type( 32 )   -- sport fishes
---------------------------------------------------------------------------------------------
 ----------  display current wheather for last 10 days from ForecastFrame.aspx.cs ----------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fnWeatherForecast' AND xtype = 'TF')
    DROP FUNCTION dbo.fnWeatherForecast
GO

CREATE FUNCTION [dbo].fnWeatherForecast( @link uniqueidentifier )
  RETURNS @TBL TABLE (dt date, wind_degree float, gpfDay float, gpfNight float, humidity int
  , wind_direction varchar(4), tmLow float, tmHigh float, wind_max_speed float, shortText varchar(255)
  , longText  varchar(255), icon  varchar(32)  )
-- WITH SCHEMABINDING
AS
BEGIN
  INSERT INTO @TBL
    SELECT dt, wind_degree, gpfDay, gpfNight, humidity, wind_direction
    , tmLow, tmHigh, wind_max_speed, shortText, longText, icon
      FROM dbo.weather_Forecast WHERE tm IS NULL AND dt >= CONVERT(VARCHAR(10),GETDATE(),101)   
        AND link = @link 
  RETURN
END  
GO  

-- select * from vStationInfo
-------------------------------------  used in a frame  --------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStationInfo' AND xtype = 'TF')
    DROP FUNCTION dbo.GetStationInfo
GO

CREATE FUNCTION [dbo].[GetStationInfo]( @fishId uniqueidentifier, @placeId bigint )
  RETURNS @TBL TABLE (wheatherStamp datetime, lat float, lon float, loadWeather int
        , county varchar(64), city varchar(64), state char(2), country char(2), locName varchar(max), id uniqueidentifier
        , today int
        , temperature float, turbidity float, oxygen float, sid int, mli varchar(64)
        , stamp datetime, discharge float, elevation float )
WITH SCHEMABINDING
    AS
    begin
      DECLARE @today int, @temperature float, @turbidity float, @oxygen float, @state char(2)
      DECLARE @stamp datetime, @discharge float, @elevation float, @locId uniqueidentifier, @shift int
      DECLARE @isw int, @wsId uniqueidentifier, @mli varchar(64)
      
      SELECT @mli = w.mli, @wsId = w.id, @today = f.today  FROM  dbo.WaterStation w 
        JOIN dbo.fish_location f ON  (w.id = f.station_Id) WHERE w.sid=@placeId and @fishId = fish_Id
    
  INSERT INTO @TBL   
    SELECT w.wheatherStamp, w.lat, w.lon, 0 as loadWeather, county, city, [state], country, locName, id, @today 
       , s.temperature, s.turbidity, s.oxygen, w.sid, w.mli, s.stamp, s.discharge, s.elevation
    FROM  dbo.vWaterStation w,  dbo.CurrentWaterState s  WHERE w.mli=s.mli AND w.sid = @placeId
    
    SELECT @stamp = stamp, @state = state FROM @TBL  
    SELECT @shift = shift FROM dbo.states WHERE state = @state
    SET @stamp = DATEADD( HOUR, -@shift, @stamp)
    SELECT @isw = COUNT(*) FROM dbo.weather_Forecast   -- check if todays weather is saved
       WHERE link= @wsId AND CONVERT(VARCHAR(10),GETDATE(),101) <= dt AND tm IS NULL
    UPDATE @TBL SET stamp = @stamp, loadWeather = ISNULL(@isw, 0)         
  return
END      
GO
--  select * from dbo.GetStationInfo( (select fish_ID from dbo.fish where fish_name='Brown Trout'), 264004)
GO  
-- select * from dbo.WaterStation where country='CA' AND state='ON'
------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByPostal' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLatLonByPostal
GO

CREATE FUNCTION dbo.GetLatLonByPostal( @postal varchar(8) )
RETURNS @TBL TABLE (lat float, lon float )
WITH SCHEMABINDING
AS
begin
  IF 1 = ISNUMERIC(@postal) AND (LEN(@postal) = 5 OR LEN(@postal) = 4)
  BEGIN
    insert into @TBL
        SELECT lat, lon FROM dbo.USPost where  zip= @postal 
  END
  ELSE
    insert into @TBL SELECT lat, lon  
      FROM dbo.CanPostLatLon  where postal=@postal
  return
end          
GO     
-- SELECT TOP 1 lat, lon FROM dbo.GetLatLonByPostal( 'V2K1G7' )
-- SELECT TOP 1 lat, lon FROM dbo.GetLatLonByPostal( '98101' )
----------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetUserLocation' AND xtype = 'TF')
    DROP FUNCTION dbo.GetUserLocation
GO    
create function dbo.GetUserLocation( @userId uniqueidentifier )
  RETURNS @TBL TABLE ( postal sysname, lat float, lon float, email sysname )
WITH SCHEMABINDING
    AS
BEGIN
  DECLARE @postal sysname, @email sysname    
  SELECT TOP 1 @postal=postal, @email=email FROM dbo.users WHERE id=@userId
--  IF 0 > LEN(@postal)
--    RETURN;
  INSERT INTO @TBL   
  select TOP 1 @postal, lat, lon, @email from dbo.GetLatLonByPostal( @postal )
  RETURN;
END
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'CheckInterval' AND xtype = 'FN')
    DROP FUNCTION dbo.CheckInterval
GO    
create function dbo.CheckInterval( @low float, @high float  )
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
  DECLARE @rst BIT
  SET @rst = 0;
  IF @low IS NOT NULL AND @high IS NOT NULL AND @high > @low 
    SET @rst = 1;
  RETURN @rst;        
END
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_latlon_byip' AND xtype = 'TF')
    DROP FUNCTION dbo.fn_map_latlon_byip
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByIP' AND xtype = 'TF')
    DROP FUNCTION dbo.GetLatLonByIP
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByIP' AND xtype = 'TF')
    DROP function dbo.GetLatLonByIP
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'IP2Int' AND xtype = 'FN')
    DROP function dbo.IP2Int
GO
CREATE function dbo.IP2Int
(@ip varchar(15))
returns bigint
WITH SCHEMABINDING
as
begin
  return cast(PARSENAME(@ip , 1) as tinyint)
    +cast(PARSENAME(@ip , 2) as tinyint)*cast(256 as bigint)
    +cast(PARSENAME(@ip , 3) as tinyint)*cast(65536 as bigint)
    +cast(PARSENAME(@ip , 4) as tinyint)*cast(16777216 as bigint)
end
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLatLonByIP' AND xtype = 'TF')
    DROP function dbo.GetLatLonByIP
GO
CREATE FUNCTION dbo.GetLatLonByIP( @ip sysname )
RETURNS @TBL TABLE (lat float, lon float )
WITH SCHEMABINDING
AS
begin
  declare @ip4 binary(4)
  SET @ip4 = CAST( dbo.IP2Int(@ip) AS binary(4) )

  if EXISTS (SELECT TOP 1 1 FROM dbo.GeoIP WHERE ip4 = @ip4)
      insert into @TBL SELECT latitude, longitude 
        FROM dbo.GeoIP WHERE ip4 = @ip4
  ELSE
    insert into @TBL (lat , lon ) VALUES (41, -80)
  return
end         
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLastHourWaterData' AND xtype = 'IF')
    DROP function dbo.GetLastHourWaterData
GO
--http://fishportal.biz/WebService/Update.aspx?WaterData=A29B196D-B909-30A0-B719-6AFC8C3DE123
--  SELECT * FROM dbo.GetLastHourWaterData( 2, 'CA', 'ON' )
CREATE FUNCTION dbo.GetLastHourWaterData( @hr int, @country char(2), @state char(2) )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
WITH cte AS
(
    SELECT MAX(stamp) AS stamp, AVG(temperature) AS temperature, AVG(discharge) AS discharge
        , AVG(turbidity) AS turbidity, AVG(oxygen) AS oxygen, AVG(ph) AS PH, AVG(elevation) AS elevation, AVG(velocity) AS velocity, mli 
        FROM dbo.vw_WaterData
        WHERE country=@country and state = @state AND stamp >= DATEADD( hour, -1 * @hr, getdate() ) 
        GROUP BY mli
)
SELECT stamp, temperature, discharge, turbidity, oxygen, ph, elevation, velocity, mli FROM cte
UNION ALL
    SELECT stamp, temperature, discharge, turbidity, oxygen, ph, elevation, velocity, mli
        FROM dbo.vw_WaterData z WHERE EXISTS
        (SELECT 1 FROM  ( SELECT MAX(stamp) AS stamp, mli FROM dbo.vw_WaterData v WHERE 
        country=@country and state = @state AND 
        NOT EXISTS (SELECT 1 FROM cte WHERE v.mli=cte.mli) GROUP BY mli )x
            WHERE z.stamp=x.stamp AND z.mli=x.mli )
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLastHourFishLocation' AND xtype = 'IF')
    DROP function dbo.GetLastHourFishLocation
GO 
--http://fishportal.biz/WebService/Update.aspx?FishLocation=75501A06-5176-4465-B299-D6041D25931C
CREATE FUNCTION dbo.GetLastHourFishLocation( @hr int )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
WITH cte  AS
(
SELECT   d.today, d.fish_id, d.station_Id
  FROM dbo.fish_location d 
    JOIN dbo.WaterStation w ON  (d.station_Id = w.id) 
    AND w.country='CA' and w.state = 'ON' AND d.stamp >= DATEADD( hour, -1, getdate() ) 
)
SELECT today, fish_id, station_Id FROM cte
UNION ALL
SELECT top 1  today, fish_id, station_Id  
  FROM dbo.fish_location d 
  JOIN dbo.WaterStation w ON (d.station_Id = w.id) --   
    AND w.country='CA' and w.state = 'ON'  
    AND EXISTS (SELECT MAX(wd.stamp)  FROM dbo.WaterData wd   where wd.stamp = d.stamp ) 
    AND NOT EXISTS ( SELECT TOP 1 1 FROM cte)
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
-- SELECT dbo.fn_CvtHexToGuid( '  {5ae76765d05211d892e2080020a0f4c9 } ' )
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'NormalizeSearch' AND xtype = 'FN')
    DROP function dbo.NormalizeSearch
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_CvtHexToGuid' AND xtype = 'FN')
    DROP function dbo.fn_CvtHexToGuid
GO
/*
	convert string form of guid typed with spaces and figure brackets into guid
*/
CREATE function dbo.fn_CvtHexToGuid( @hex varchar(64)  )
RETURNS uniqueidentifier
WITH SCHEMABINDING
AS
BEGIN
    RETURN 
		( SELECT CAST(val AS uniqueidentifier) AS val
		  FROM  (SELECT LEFT(val, 8) + '-' + SUBSTRING(val, 9, 4) + '-' + SUBSTRING(val, 13, 4)  + '-' + SUBSTRING(val, 17, 4)+ '-' + SUBSTRING(val, 21, 12) AS val 
					FROM (SELECT UPPER(RTRIM(LTRIM(val))) AS val FROM (VALUES (REPLACE(REPLACE(@hex, '{', ''), '}', ''))) x(val) )y )z 
		   WHERE TRY_CONVERT(UNIQUEIDENTIFIER, val) IS NOT NULL
		)
END
GO
-------------------------------------------------------------------------------------------------------
-- SELECT dbo.NormalizeSearch( ' {5bcf4766-dc35-435c-97b1-733fd8675049} ' )
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'NormalizeSearch' AND xtype = 'FN')
    DROP function dbo.NormalizeSearch
GO

CREATE FUNCTION dbo.NormalizeSearch( @search nvarchar(255) )
RETURNS nvarchar(255)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @result nvarchar(255)

    set @result = LTRIM(RTRIM(@search))
    set @result  = replace( @result, char(13), ' ')
    set @result  = replace( @result, char(10), ' ')
    set @result  = replace( @result, ',', ' ')
    set @result  = replace( @result, ')', ' ')
    set @result  = replace( @result, '  ', ' ')
	set @result  = replace( @result, '{', '')
	set @result  = replace( @result, '}', '')
	SET @result = LTRIM(RTRIM(@result))

    -- set @search  = SELECT STUFF(@search,PATINDEX('%[A-Z0-9][A-Z0-9].[A-Z0-9][A-Z0-9].[A-Z0-9][A-Z0-9][A-Z0-9] %'COLLATE Cyrillic_General_BIN,@search),10,'');

    IF LEN(@result) = 32 AND ( @result LIKE '%[0-9]%' OR @result LIKE '%[abcdefABCDEF]%' )
    BEGIN
        SET @result = CAST(dbo.fn_CvtHexToGuid(@search) AS char(36))
    END
	IF @result = '.'
		SET @result = NULL
	RETURN NULLIF(@result, '')
END
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchLakeList' AND xtype = 'TF')
    DROP function dbo.SearchLakeList
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceSearchVariant' AND xtype = 'TF')
    DROP function dbo.ProduceSearchVariant
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceWBVariant' AND xtype = 'TF')
    DROP function dbo.ProduceWBVariant
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetWaterType' AND xtype = 'FN')
    DROP function dbo.GetWaterType
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetValidPart' AND xtype = 'FN')
    DROP function dbo.GetValidPart
GO
-- Function: dbo.GetValidPart
-- Description: This function processes an input string of space-separated words to identify the most relevant water body name from a predefined list. 
--              The function considers both English and French synonyms for water body names and returns the English equivalent of the last valid name found in the input. 
--              If the last part is not a valid water body name, the function returns the first valid name instead.
-- 
-- Parameters:
--   @search_names (sysname): A space-separated string containing potential water body names to be evaluated.
-- 
-- Returns:
--   sysname: The English equivalent of the last valid water body name found in the input string, or the first valid name if the last one is invalid.
-- 
-- Logic:
--   1. Valid names are derived from the dbo.water_body table, considering both English and French synonyms.
--   2. The input string is split into individual words, each assigned a positional order.
--   3. Words are validated against the list of water body names, mapping French names to their English equivalents.
--   4. If the last valid name exists in the input string, it is returned; otherwise, the first valid name is returned.
-- 
-- Examples:
--   SELECT dbo.GetValidPart('first lake river'); -- Returns 'river'
--   SELECT dbo.GetValidPart('lake second Pond'); -- Returns 'Pond'
--   SELECT dbo.GetValidPart('Lac gold');         -- Returns 'Lake'
CREATE FUNCTION dbo.GetValidPart (
    @search_names sysname
)
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @result sysname;

    -- Define the list of valid names (English and French synonyms)
    WITH valid_parts AS (
        SELECT en AS part
        FROM dbo.water_body
        UNION
        SELECT fr AS part
        FROM dbo.water_body
    ),
    english_parts AS (
        SELECT en AS english_part, fr AS french_part
        FROM dbo.water_body
    ),
    -- Split search names into individual parts
    split_names AS (
        SELECT 
            @search_names AS name,
            value AS part,
            ROW_NUMBER() OVER (ORDER BY CHARINDEX(value, @search_names)) AS position
        FROM STRING_SPLIT(@search_names, ' ')
    ),
    -- Check which parts are valid and map to English equivalents
    valid_names AS (
        SELECT DISTINCT 
            s.name,
            s.part,
            s.position,
            ISNULL(ep.english_part, s.part) AS english_part,
            CASE WHEN s.part IN (SELECT part FROM valid_parts) THEN 1 ELSE 0 END AS is_valid
        FROM split_names s
        LEFT JOIN english_parts ep ON s.part = ep.french_part OR s.part = ep.english_part
    ),
    -- Identify the last valid part or the first valid part
    ranked_parts AS (
        SELECT 
            name,
            part,
            english_part,
            position,
            is_valid
        FROM valid_names
        WHERE is_valid = 1
    )
    -- Select the appropriate part
    SELECT TOP 1 @result = 
        CASE 
            WHEN EXISTS (SELECT 1 FROM ranked_parts WHERE position = (SELECT MAX(position) FROM ranked_parts)) THEN 
                (SELECT TOP 1 english_part FROM ranked_parts ORDER BY position DESC)
            ELSE 
                (SELECT TOP 1 english_part FROM ranked_parts ORDER BY position ASC)
        END
    FROM ranked_parts;

    RETURN @result;
END;
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchLakeList' AND xtype = 'TF')
    DROP function dbo.SearchLakeList
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceSearchVariant' AND xtype = 'TF')
    DROP function dbo.ProduceSearchVariant
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetWaterType' AND xtype = 'FN')
    DROP function dbo.GetWaterType
GO
/*
    SELECT dbo.GetWaterType( 'Lake Huron' ), dbo.GetWaterType( 'Grand River' ), dbo.GetWaterType( 'Biver Creek' ), dbo.GetWaterType( 'Gold Pond' )
*/
CREATE FUNCTION dbo.GetWaterType( @search sysname )
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    -- Return NULL if the input is NULL or an empty string
    IF NULLIF(@search, '') IS NULL
        RETURN NULL;

    -- Declare a variable to store the result
    DECLARE @result INT;

    -- Fetch the water type based on the valid part of the search
    SELECT TOP 1 @result = loctype 
    FROM dbo.water_body b
    WHERE dbo.GetValidPart(@search) = b.en;

    -- Return the result, or NULL if no match is found
    RETURN @result;
END;
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceSearchVariant' AND xtype = 'TF')
    DROP FUNCTION dbo.ProduceSearchVariant
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceWBVariant' AND xtype = 'TF')
    DROP FUNCTION dbo.ProduceWBVariant
GO
/*
    remove water body from name and produce all name variants
    select * FROM dbo.ProduceWBVariant( 'Naftel''s Creek' )
    select * FROM dbo.ProduceWBVariant( 'st. Peter' )
*/
CREATE FUNCTION dbo.ProduceWBVariant( @search sysname )
RETURNS @comb TABLE (
      line  sysname NOT NULL
    , irank int     DEFAULT 0
    , id    int     NOT NULL IDENTITY(1,1)
)
WITH SCHEMABINDING
AS
BEGIN
    IF NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL
        RETURN

    DECLARE @mix TABLE ( line sysname, ln int IDENTITY(1,1) )

    INSERT INTO @mix (line)
        SELECT RTRIM(LTRIM([value]))
        FROM STRING_SPLIT(@search, N' ')
        WHERE NULLIF(RTRIM(LTRIM([value])), N'') IS NOT NULL

    DECLARE @cnt int = (SELECT MAX(ln) FROM @mix)

    -- find type of water body
    DECLARE @bodytype int = dbo.GetWaterType(@search)

    -- delete type of waterbody from name
    DELETE FROM @mix
    WHERE line IN (
            SELECT en FROM dbo.water_body WHERE en = dbo.GetValidPart(@search)
            UNION
            SELECT fr FROM dbo.water_body WHERE en = dbo.GetValidPart(@search)
        )

    SET @cnt = @cnt - 1

    -- make combinations (preserve earlier behavior)
    INSERT INTO @comb (line, irank)
        SELECT line, @cnt + 1
        FROM @mix

    IF @cnt = 2
    BEGIN
        INSERT INTO @comb (line, irank)
            SELECT m1.line + N' ' + m2.line, 2
            FROM @mix m1, @mix m2
            WHERE m1.line <> m2.line
    END
    ELSE IF @cnt = 3
    BEGIN
        INSERT INTO @comb (line, irank)
            SELECT m1.line + N' ' + m2.line + N' ' + m3.line, 2
            FROM @mix m1, @mix m2, @mix m3
            WHERE m1.line <> m2.line
              AND m1.line <> m3.line
              AND m2.line <> m3.line

        INSERT INTO @comb (line, irank)
            SELECT m1.line + N' ' + m2.line, 3
            FROM @mix m1, @mix m2, @mix m3
            WHERE m1.line <> m2.line
              AND m1.line <> m3.line
              AND m2.line <> m3.line
            UNION
            SELECT m2.line + N' ' + m3.line, 3
            FROM @mix m1, @mix m2, @mix m3
            WHERE m1.line <> m2.line
              AND m1.line <> m3.line
              AND m2.line <> m3.line
    END
    ELSE IF @cnt = 4
    BEGIN
        INSERT INTO @comb (line, irank)
            SELECT m1.line + N' ' + m2.line + N' ' + m3.line + N' ' + m4.line, 2
            FROM @mix m1, @mix m2, @mix m3, @mix m4
            WHERE m1.line <> m2.line
              AND m1.line <> m3.line
              AND m1.line <> m4.line
              AND m2.line <> m3.line
              AND m2.line <> m4.line
              AND m3.line <> m4.line
    END
    ELSE
    BEGIN
        INSERT INTO @comb (line, irank)
            SELECT line, 1
            FROM @mix
    END

    -- delete duplicates (keep lowest irank)
    DELETE x
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY line ORDER BY irank, id) AS rn
        FROM @comb
    ) x
    WHERE x.rn > 1

    ------------------------------------------------------------------
    -- add variant based on synonyms  (St. <-> Santa)
    ------------------------------------------------------------------
    DECLARE @expansions TABLE (line sysname NOT NULL, irank int NOT NULL)

    INSERT INTO @expansions (line, irank)
        SELECT DISTINCT REPLACE(c.line, N'St.', N'Santa'), c.irank + 1
        FROM @comb c
        WHERE (' ' + c.line + ' ') LIKE N'% St. %' OR c.line = N'St.'

    INSERT INTO @expansions (line, irank)
        SELECT DISTINCT REPLACE(c.line, N'Santa', N'St.'), c.irank + 1
        FROM @comb c
        WHERE (' ' + c.line + ' ') LIKE N'% Santa %' OR c.line = N'Santa'

    INSERT INTO @comb (line, irank)
        SELECT e.line, e.irank
        FROM @expansions e
        WHERE NOT EXISTS (SELECT 1 FROM @comb c WHERE c.line = e.line)

    ------------------------------------------------------------------
    -- add variant stripped of surrounding matching quotes ("x" or 'x')
    ------------------------------------------------------------------
    DECLARE @unquoted TABLE (line sysname NOT NULL, irank int NOT NULL)

    INSERT INTO @unquoted (line, irank)
        SELECT SUBSTRING(c.line, 2, LEN(c.line) - 2), c.irank + 1
        FROM @comb c
        WHERE LEN(c.line) >= 2
          AND (
                (LEFT(c.line, 1) = N'"'  AND RIGHT(c.line, 1) = N'"')
             OR (LEFT(c.line, 1) = N'''' AND RIGHT(c.line, 1) = N'''')
          )
          AND NULLIF(LTRIM(RTRIM(SUBSTRING(c.line, 2, LEN(c.line) - 2))), N'') IS NOT NULL

    INSERT INTO @comb (line, irank)
        SELECT u.line, u.irank
        FROM @unquoted u
        WHERE NOT EXISTS (SELECT 1 FROM @comb c WHERE c.line = u.line)

    ------------------------------------------------------------------
    -- add variant with apostrophe-s removed / collapsed
    --   Blackie's -> Blackies / Blackie
    ------------------------------------------------------------------
    DECLARE @sforms TABLE (line sysname NOT NULL, irank int NOT NULL)

    INSERT INTO @sforms (line, irank)
        SELECT REPLACE(c.line, N'''s', N's'), c.irank + 1
        FROM @comb c
        WHERE c.line LIKE N'%''s' OR c.line LIKE N'%''s %'

    INSERT INTO @sforms (line, irank)
        SELECT REPLACE(c.line, N'''s', N''), c.irank + 1
        FROM @comb c
        WHERE c.line LIKE N'%''s' OR c.line LIKE N'%''s %'

    INSERT INTO @comb (line, irank)
        SELECT s.line, s.irank
        FROM @sforms s
        WHERE NULLIF(LTRIM(RTRIM(s.line)), N'') IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM @comb c WHERE c.line = s.line)

    ------------------------------------------------------------------
    -- add variant without trailing exclamation mark
    ------------------------------------------------------------------
    DECLARE @bang TABLE (line sysname NOT NULL, irank int NOT NULL)

    INSERT INTO @bang (line, irank)
        SELECT REPLACE(c.line, N'!', N''), c.irank + 1
        FROM @comb c
        WHERE RIGHT(c.line, 1) = N'!'
          AND NULLIF(LTRIM(RTRIM(REPLACE(c.line, N'!', N''))), N'') IS NOT NULL

    INSERT INTO @comb (line, irank)
        SELECT b.line, b.irank
        FROM @bang b
        WHERE NOT EXISTS (SELECT 1 FROM @comb c WHERE c.line = b.line)

    ------------------------------------------------------------------
    -- restore @search without bodytype and mark it as irank 1
    ------------------------------------------------------------------
    DECLARE @srch sysname = N''
    SELECT @srch = CASE WHEN @srch = N'' THEN line ELSE @srch + N' ' + line END
    FROM @mix
    ORDER BY ln ASC

    IF @srch <> N''
        UPDATE @comb SET irank = 1 WHERE line = @srch

    -- final cleanup: remove any stray water-body-type words
    DELETE FROM @comb
    WHERE line IN (
          N'arm', N'creek', N'lake', N'stream', N'channel', N'pond', N'marsh'
        , N'backwater', N'canal', N'estuary', N'shore', N'drain', N'ditch'
        , N'wetland', N'reservoir', N'sea'
    )

    DELETE FROM @comb
    WHERE line IN (
          N'bras', N'ruisseau', N'lac', N'étang', N'marais', N'eau stagnante'
        , N'estuaire', N'rivage', N'fosse', N'réservoir', N'mer'
    )

    -- final dedupe again after all staged inserts
    DELETE x
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY line ORDER BY irank, id) AS rn
        FROM @comb
    ) x
    WHERE x.rn > 1

    RETURN
END
GO
-------------------------------------------------------------------------------------------------------
-- SELECT * FROM dbo.ProduceSearchVariant( ' Lake St. Francis ' )
-- SELECT * FROM dbo.ProduceSearchVariant( ' MOSQUITO CREEK' )
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchLakeList' AND xtype = 'TF')
    DROP function dbo.SearchLakeList
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceSearchVariant' AND xtype = 'TF')
    DROP function dbo.ProduceSearchVariant
GO
/*
	make all possible combinations of names with using english or french names of water body
	SELECT * FROM dbo.ProduceSearchVariant( ' Lake St. Francis ' ) order by irank ASC
    SELECT * FROM dbo.ProduceSearchVariant(  N'North Sigma River' ) order by irank ASC
*/
CREATE FUNCTION dbo.ProduceSearchVariant( @search sysname )
RETURNS @result TABLE (
      line  sysname NOT NULL
    , irank int     NOT NULL
)
WITH SCHEMABINDING
AS
BEGIN
    IF NULLIF(LTRIM(RTRIM(@search)), N'') IS NULL
        RETURN

    DECLARE @trim sysname = LTRIM(RTRIM(@search))

    -- make combinations
    DECLARE @comb TABLE (
          line  sysname NOT NULL
        , irank int     DEFAULT 0
        , id    int     NOT NULL IDENTITY(1,1)
    )

    INSERT INTO @comb (line, irank)
        SELECT line, irank
        FROM dbo.ProduceWBVariant(@trim)

    IF EXISTS (SELECT 1 FROM @comb WHERE RIGHT(line, 1) = N'!')
        INSERT INTO @result (line, irank)
            SELECT REPLACE(@trim, N'!', N''), 1

    INSERT INTO @result (line, irank)
        VALUES (@trim, 0)

    ------------------------------------------------------------------
    -- prefix each @comb row with known modifiers, but stage first
    ------------------------------------------------------------------
    DECLARE @mods TABLE (val sysname NOT NULL PRIMARY KEY)
    INSERT INTO @mods (val)
    VALUES
          (N'Big'), (N'Small'), (N'Little')
        , (N'Left'), (N'La gauche')
        , (N'Right'), (N'Droite')
        , (N'Upper'), (N'Lower')
        , (N'North'), (N'Nord')
        , (N'South'), (N'Sud')
        , (N'West'), (N'Ouest')
        , (N'East'), (N'est')

    DECLARE @pref TABLE (line sysname NOT NULL, irank int NOT NULL)
    INSERT INTO @pref (line, irank)
        SELECT m.val + N' ' + c.line, c.irank + 1
        FROM @comb c
        CROSS JOIN @mods m
        WHERE c.line NOT LIKE (m.val + N' %')

    INSERT INTO @comb (line, irank)
        SELECT p.line, p.irank
        FROM @pref p
        WHERE NOT EXISTS (SELECT 1 FROM @comb c WHERE c.line = p.line)

    DECLARE @bodytype int = dbo.GetWaterType(@trim)
    DECLARE @body_en sysname = dbo.GetValidPart(@trim)
    DECLARE @body_fr sysname

    SELECT TOP 1 @body_fr = fr
    FROM dbo.water_body
    WHERE en = @body_en

    -- add all combinations of water body (historical behavior)
    IF @bodytype IS NOT NULL
    BEGIN
        DECLARE @prepare TABLE ( line sysname NOT NULL, irank int NOT NULL )

        ;WITH cte (val) AS
        (
            SELECT en FROM dbo.water_body WHERE locType = @bodytype
            UNION
            SELECT fr FROM dbo.water_body WHERE locType = @bodytype
        )
        INSERT INTO @prepare (line, irank)
            SELECT val + N' ' + c.line, c.irank
            FROM @comb c CROSS JOIN cte
            UNION
            SELECT c.line + N' ' + val, c.irank
            FROM @comb c CROSS JOIN cte

        INSERT INTO @result (line, irank)
            SELECT p.line, MIN(p.irank)
            FROM @prepare p
            WHERE NOT EXISTS (SELECT 1 FROM @result r WHERE r.line = p.line)
            GROUP BY p.line
    END
    ELSE
    BEGIN
        INSERT INTO @result (line, irank)
            SELECT DISTINCT c.line, 1
            FROM @comb c
            WHERE NOT EXISTS (SELECT 1 FROM @result r WHERE r.line = c.line)
    END

    ------------------------------------------------------------------
    -- targeted repair pass for the four known edge cases
    ------------------------------------------------------------------
    IF @body_en IS NOT NULL
    BEGIN
        DECLARE @core_alt sysname = NULL
        DECLARE @core_apos sysname = NULL
        DECLARE @core_unq sysname = NULL
        DECLARE @body_repair TABLE (line sysname NOT NULL, irank int NOT NULL)

        -- 1) St. <-> Santa repair, add canonical English-suffix form
        IF @trim LIKE N'%St.%' OR @trim LIKE N'%Santa%'
        BEGIN
            SELECT TOP 1 @core_alt =
                CASE
                    WHEN line LIKE N'%St.%'   THEN REPLACE(line, N'St.', N'Santa')
                    WHEN line LIKE N'%Santa%' THEN REPLACE(line, N'Santa', N'St.')
                    ELSE NULL
                END
            FROM dbo.ProduceWBVariant(@trim)
            WHERE line LIKE N'%St.%' OR line LIKE N'%Santa%'
            ORDER BY LEN(line) DESC, irank ASC

            IF NULLIF(@core_alt, N'') IS NOT NULL
            BEGIN
                INSERT INTO @body_repair (line, irank)
                VALUES (@core_alt + N' ' + @body_en, 1)
            END
        END

        -- 2) Apostrophe-s repair, add canonical French-prefix form
        IF @trim LIKE N'%''s%' OR @trim LIKE N'%''S%'
        BEGIN
            SELECT TOP 1 @core_apos = REPLACE(line, N'''s', N's')
            FROM dbo.ProduceWBVariant(@trim)
            WHERE line LIKE N'%''s%' OR line LIKE N'%''S%'
            ORDER BY LEN(line) DESC, irank ASC

            IF NULLIF(@core_apos, N'') IS NOT NULL AND @body_fr IS NOT NULL
            BEGIN
                INSERT INTO @body_repair (line, irank)
                VALUES (@body_fr + N' ' + @core_apos, 1)
            END
        END

        -- 3) Matching quote repair, add canonical English-suffix unquoted form
        IF LEFT(@trim, 1) IN (N'"', N'''')
        BEGIN
            SELECT TOP 1 @core_unq =
                CASE
                    WHEN LEN(line) >= 2
                     AND ((LEFT(line,1) = N'"' AND RIGHT(line,1) = N'"')
                       OR (LEFT(line,1) = N'''' AND RIGHT(line,1) = N''''))
                    THEN SUBSTRING(line, 2, LEN(line) - 2)
                    ELSE NULL
                END
            FROM dbo.ProduceWBVariant(@trim)
            WHERE LEN(line) >= 2
              AND ((LEFT(line,1) = N'"' AND RIGHT(line,1) = N'"')
                OR (LEFT(line,1) = N'''' AND RIGHT(line,1) = N''''))
            ORDER BY LEN(line) ASC, irank ASC

            IF NULLIF(@core_unq, N'') IS NOT NULL
            BEGIN
                INSERT INTO @body_repair (line, irank)
                VALUES (@core_unq + N' ' + @body_en, 1)
            END
        END

        INSERT INTO @result (line, irank)
            SELECT br.line, br.irank
            FROM @body_repair br
            WHERE NOT EXISTS (SELECT 1 FROM @result r WHERE r.line = br.line)
    END

    DELETE x
    FROM (
        SELECT line,
               ROW_NUMBER() OVER (PARTITION BY line ORDER BY irank, line) AS rn
        FROM @result
    ) x
    WHERE x.rn > 1

    RETURN
END
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchLakeList' AND xtype = 'TF')
    DROP function dbo.SearchLakeList
GO

-- select * from dbo.SearchLakeList( 'Tim Lake' )
-- select * from dbo.SearchLakeList( '0c5210db849c20c357f421ff96a2047b' )
CREATE FUNCTION dbo.SearchLakeList( @search sysname )
  RETURNS @rst TABLE ( num int NOT NULL identity primary key, lake_name nvarchar(64), irank int, alt_name nvarchar(64), lake_id uniqueidentifier, locType int
                     , country char(2), state char(2), county nvarchar(64)
                     , source_name nvarchar(64) , mouth_name nvarchar(64), [description] nvarchar(1024)
                     , source_lat float, source_lon float, source uniqueidentifier, mouth uniqueidentifier
                     , zone int, isWell bit, isFish bit, source_state char(2), mouth_state char(2)
                     , source_country char(2), mouth_country char(2), mouth_lat float, mouth_lon float
                     , source_loc nvarchar(2048), mouth_loc nvarchar(2048), CGNDB varchar(32))
    AS
begin
    set @search = dbo.NormalizeSearch( @search ) -- remove garbige symbols from search string

    declare  @resultid TABLE ( lake_id uniqueidentifier not null, irank int )

	declare @comb TABLE( line sysname, irank int ); 
	INSERT INTO @comb SELECT line, irank FROM dbo.ProduceSearchVariant( @search )

	IF TRY_CONVERT(UNIQUEIDENTIFIER, dbo.fn_CvtHexToGuid( @search )) IS NOT NULL
		SET @search = dbo.fn_CvtHexToGuid( @search )

	IF TRY_CONVERT(UNIQUEIDENTIFIER, @search ) IS NOT NULL
        insert into @resultid (lake_id, irank) SELECT @search, 0

    IF NOT EXISTS (SELECT * FROM @resultid)    
    BEGIN
        insert into @resultid (lake_id, irank)
           select DISTINCT lake_id, 0 from dbo.lake l where @search = CGNDB

        IF NOT EXISTS (SELECT * FROM @resultid)    
        BEGIN
            insert into @resultid (lake_id, irank)
               select lake_id, irank from dbo.lake l WITH (INDEX (idx_Lake_alt_name)) JOIN @comb c ON c.line = alt_name

            insert into @resultid (lake_id, irank)
               select lake_id, irank from dbo.lake l WITH (INDEX (idx_Lake_name)) JOIN @comb c ON c.line = lake_name  

            insert into @resultid (lake_id, irank)
               select lake_id, irank from dbo.lake l WITH (INDEX (idx_Lake_french_name)) JOIN @comb c ON c.line = french_name

            insert into @resultid (lake_id, irank)
               select lake_id, irank from dbo.lake l WITH (INDEX (idx_Lake_native)) JOIN @comb c ON c.line = [native] 

            IF NOT EXISTS (SELECT * FROM @resultid)    
            BEGIN
                insert into @resultid (lake_id, irank)
                   select DISTINCT lake_id, 3 from dbo.lake l where lake_name like N'%' + @search + N'%'

                insert into @resultid (lake_id, irank)
                   select DISTINCT lake_id, 3 from dbo.lake l where alt_name like N'%' + @search + N'%' AND alt_name IS NOT NULL
            END
        END
    END
    delete x from (  select lake_id, rn=row_number() over (partition by lake_id order by irank)  from @resultid) x where rn > 1;

    INSERT INTO @rst SELECT lake_name, irank, alt_name, l.lake_id, locType
        , country, state, county, source_name, mouth_name
        , CASE WHEN county IS NULL THEN state ELSE county END AS [description]
        , lat, lon, null, null, zone, isWell, isFish
        , source_state, mouth_state, source_country, mouth_country
        , mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB
        FROM vw_lake l JOIN @resultid r ON  r.lake_id = l.lake_id
   RETURN
end
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchFishList' AND xtype = 'TF')
    DROP function dbo.SearchFishList
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'FishSearchVariant' AND xtype = 'TF')
    DROP function dbo.FishSearchVariant
GO
/*
	make all possible combinations of names
	SELECT * FROM dbo.FishSearchVariant( 'Sucker, Longnose' ) order by irank ASC
	SELECT * FROM dbo.FishSearchVariant( 'Salmon' ) order by irank ASC
    SELECT * FROM dbo.FishSearchVariant( 'Northern Pike' ) order by irank ASC
*/
CREATE FUNCTION dbo.FishSearchVariant( @search nvarchar(255) )
RETURNS @result TABLE ( line sysname NOT NULL PRIMARY KEY, irank int ) 
WITH SCHEMABINDING
AS
BEGIN
	IF NULLIF(@search, '') IS NULL
		RETURN

    SET @search = REPLACE( @search, N',', N' ');
    SET @search = REPLACE( @search, N'  ', N' ');

    IF EXISTS (SELECT 1 FROM dbo.fish WHERE fish_name = @search)
    BEGIN
    	INSERT INTO @result SELECT fish_name, 0 FROM dbo.fish WHERE fish_name = @search
        RETURN
    END	
    IF EXISTS (SELECT 1 FROM dbo.fish WHERE fish_latin = @search)
    BEGIN
    	INSERT INTO @result SELECT fish_name, 0 FROM dbo.fish WHERE fish_name = @search
        RETURN
    END	

    DECLARE @mix   TABLE ( line sysname, ln int IDENTITY(1,1) )

    INSERT INTO @mix (line) 
        SELECT RTRIM(LTRIM([value])) AS name FROM STRING_SPLIT(@search,' ') WHERE NULLIF([value], '') IS NOT NULL

    UPDATE @mix SET line = LEFT(line, LEN(line)-1) WHERE RIGHT(line, 1) = ','  -- remove comma symbol
    
	DECLARE @cnt int = (SELECT MAX(ln) FROM @mix)

	-- make combinations
	DECLARE @comb TABLE ( line sysname NOT NULL, irank int DEFAULT 0, id int not null identity(1,1)) 

    INSERT INTO @comb  SELECT line, @cnt + 1 FROM @mix

	IF @cnt = 2
    BEGIN
		INSERT INTO @comb  SELECT m1.line + ' ' + m2.line as line, 2 FROM @mix m1, @mix m2 WHERE m1.line <> m2.line
        -- set comma after first word
		INSERT INTO @comb  SELECT m1.line + ', ' + m2.line as line, 2 FROM @mix m1, @mix m2 WHERE m1.line <> m2.line
    END ELSE
	IF @cnt > 2
    BEGIN
	    INSERT INTO @comb
		    SELECT m1.line + ' ' + m2.line + ' ' + m3.line as line, 2 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line

	    INSERT INTO @comb
		    SELECT m1.line + ', ' + m2.line + ' ' + m3.line as line, 2 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
	    INSERT INTO @comb
		    SELECT m1.line + ' ' + m2.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
            UNION 
		    SELECT m2.line + ' ' + m3.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
            UNION 
		    SELECT m1.line + ', ' + m2.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
            UNION 
		    SELECT m2.line + ', ' + m3.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
    END
	ELSE 
		INSERT INTO @comb select line, 1 FROM @mix

    -- delete duplicats
    delete x from (  select line, rn=row_number() over (partition by line order by irank ASC)  from @comb) x where rn > 1;

	INSERT INTO @result SELECT @search, 0 WHERE NOT EXISTS (SELECT line FROM @result r WHERE r.line = @search)

    INSERT INTO @result SELECT DISTINCT line, irank FROM @comb c WHERE NOT EXISTS (SELECT line FROM @result r WHERE r.line = c.line)

	RETURN
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'SearchFishList' AND xtype = 'TF')
    DROP function dbo.SearchFishList
GO

-- search fish by any alternative name
-- select * from dbo.SearchFishList('rosefish ')    -- Bluegill
-- select * from dbo.SearchFishList('Northern Pike ')    -- Bluegill
CREATE FUNCTION dbo.SearchFishList( @search varchar(64) )
  RETURNS @rst TABLE ( num int identity, fish_name nvarchar(64), name nvarchar(64), fish_latin varchar(64), fish_id uniqueidentifier, irank int )
    AS
begin
    declare @origin varchar(64) = @search
    set @search = dbo.NormalizeSearch( @search ) -- remove garbige symbols from search string

    -- single result then return it
    if( 1 = (select count(*) from fish where fish_name LIKE @search OR fish_latin LIKE @search ) )
    begin
      insert into @rst select fish_name, fish_name, fish_latin, fish_id, 0 from fish  
        where @search = fish_name or @search = fish_latin OR @origin = fish_name or @origin = fish_latin
      update f set f.name = o.name from @rst f join vFishOK o on (f.fish_id=o.fish_id)
      RETURN
    end

    declare  @resultid TABLE ( fish_id uniqueidentifier not null primary key, irank int not null )
	declare @comb TABLE( line sysname, irank int not null); 
	INSERT INTO @comb SELECT DISTINCT line, 1 FROM dbo.FishSearchVariant( @search )

    delete x from (  select line, rn=row_number() over (partition by line order by irank)  from @comb) x where rn > 1;

    MERGE INTO @comb AS t
        USING (select @origin, 0) AS s(line, irank)  ON t.line = s.line
    WHEN MATCHED THEN 
        UPDATE SET irank = 0
    WHEN NOT MATCHED BY TARGET THEN  
        INSERT (line, irank) VALUES ( @origin, 0);

    insert into @resultid (fish_id, irank)
        select DISTINCT fish_id, c.irank from dbo.fish JOIN @comb c ON line like fish_name
            AND NOT EXISTS (SELECT * FROm @resultid t WHERE t.fish_id = fish_id)

    insert into @resultid (fish_id, irank)
		SELECT f.fish_id, MIN(c.irank + 1) AS RankValue FROM dbo.fish f
			CROSS APPLY STRING_SPLIT(f.alt_name, ';') x
			JOIN @comb c ON c.line LIKE x.value
		WHERE NOT EXISTS ( SELECT 1  FROM @resultid t WHERE t.fish_id = f.fish_id)
		GROUP BY f.fish_id;

    insert into @resultid (fish_id, irank)
        SELECT fish_id, irank FROM
        (
            SELECT fish_id, MIN(irank) AS irank FROM
            (
                SELECT DISTINCT fish_id, c.irank + 2 AS irank from dbo.fish JOIN @comb c ON fish_name like ('%' + line + '%')
            )x  GROUP BY fish_id
        )z WHERE NOT EXISTS (SELECT * FROM @resultid t WHERE t.fish_id = z.fish_id)

    insert into @rst select fish_name, fish_name, fish_latin, f.fish_id , irank
        from fish f JOIN @resultid r ON r.fish_id = f.fish_id
   RETURN
end
GO
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_only_river_list' AND xtype = 'IF')
    DROP function dbo.fn_only_river_list
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_first_item' AND xtype = 'FN')
    DROP function dbo.fn_first_item
GO

-- return first item from list if it's a list or value as is
create FUNCTION dbo.fn_first_item( @list NVARCHAR(max))
RETURNS nvarchar(128)
--WITH SCHEMABINDING
AS
BEGIN
  DECLARE @result nvarchar(128) = ( SELECT TOP 1 item FROM dbo.fn_Parser(@list) );
  RETURN @result
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_list')
    DROP function dbo.fn_river_list
GO
/*
    Display list of rivers
    Used in FishTracker.Resources.Water.LoadRiver
-- DROP  FUNCTION dbo.fn_river_list
-- used in RiverList
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', 2, N'R', 0, 1, 0)    ORDER BY lake_name ASC
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', 2, N'$', 0, 0, 0) ORDER BY num ASC
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', '2', N'E', 0, 0 ) ORDER BY lake_name ASC
     SELECT DISTINCT LEFT(lake_name, 1) FROM dbo.fn_river_list( 'ON', 'CA', 2, '$', 1, 0, 0) ORDER BY 1 ASC
     SELECT DISTINCT symbol FROM dbo.fn_river_list('ON', 'CA', 1, '$', 0, 0, 1)
-- SELECT * FROM lake where lake_name = 'Grand River'
-- SELECT * FROM lake where lake_name = 'Seguin River'
*/
CREATE FUNCTION dbo.fn_river_list( @state char(2), @country char(2), @river int, @section nchar, @monitor bit, @fish bit, @page int = 0 )
RETURNS TABLE
WITH SCHEMABINDING 
RETURN 
    WITH cte
    AS
    (
        SELECT l.lat, l.lon, l.lake_name, l.alt_Name, l.county, l.lake_id, l.state, l.country
                , left(COALESCE(source_loc, mouth_loc), 32) AS [description] 
                , l.zone, l.IsFish, l.isWell, l.source_name, l.mouth_name, source_lat, source_lon, mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB
                , COALESCE(source_loc, mouth_loc, CGNDB) AS guidloc, symbol, reviewed, l.noFish
            FROM dbo.vw_lake l
            WHERE @state IN (source_state, mouth_state) AND @river = l.locType
            AND (   ISNULL(isFish,0) = (CASE WHEN @fish = 1 THEN 1 ELSE 0 END)
                 OR (@fish = 0 AND ISNULL(noFish,0) = 1) )
            AND ISNULL(isWell,0)  = (CASE WHEN @monitor = 1 THEN 1 ELSE 0 END)
            AND l.lake_id IN (SELECT lake_id FROM dbo.lake WHERE symbol in ('0','1','2','3','4','5','6','7','8','9')
                        UNION SELECT lake_id FROM dbo.lake WHERE symbol=UPPER(@section)
                        UNION SELECT lake_id FROM dbo.lake WHERE @section='$'  )
    )SELECT num, lat, lon, lake_name, alt_Name, county, lake_id, state, country, [description], zone
        , IsFish, isWell, source_name, mouth_name, source_lat, source_lon, mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB, guidloc 
        , x.cnt AS itg, sym, noFish, reviewed
        FROM
        (
            SELECT ROW_NUMBER() Over(Order by (Select 1)) AS num, lat, lon, lake_name, alt_Name, county, lake_id, state
                 , country, [description], zone, IsFish, isWell, source_name, mouth_name, source_lat, source_lon
                 , mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB, guidloc, symbol AS sym, reviewed, noFish FROM cte
        )z, (SELECT COUNT(*) AS cnt FROM cte)x
        ORDER BY num ASC OFFSET @page * 25 ROWS FETCH NEXT 25 ROWS ONLY
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_sym')
    DROP function dbo.fn_river_sym
GO
/*
    Display list of rivers
    Used in FishTracker.Resources.Water.LoadRiver
-- DROP  FUNCTION dbo.fn_river_list
-- used in RiverList
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', 1, N'A', 0, 0, 2) ORDER BY lake_name ASC
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', 2, N'$', 0, 0, 0) ORDER BY num ASC
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', '2', N'E', 0, 0 ) ORDER BY lake_name ASC
   SELECT DISTINCT symbol FROM dbo.fn_river_sym('ON', 'CA', 1, '$', 0, 0)
-- SELECT * FROM lake where lake_name = 'Grand River'
*/
CREATE FUNCTION dbo.fn_river_sym( @state char(2), @country char(2), @river int, @section nchar, @monitor bit, @fish bit )
RETURNS TABLE
WITH SCHEMABINDING 
RETURN 
    SELECT symbol FROM dbo.vw_lake
        WHERE @state IN (source_state, mouth_state) AND @river = locType
        AND ISNULL(isFish,0)  = (CASE WHEN @fish    = 1 THEN 1 ELSE 0 END)
        AND ISNULL(isWell,0)  = (CASE WHEN @monitor = 1 THEN 1 ELSE 0 END)
        AND lake_id IN (SELECT lake_id FROm dbo.lake WHERE symbol in ('0','1','2','3','4','5','6','7','8','9')
                    UNION SELECT lake_id FROm dbo.lake WHERE symbol=UPPER(@section)
                    UNION SELECT lake_id FROm dbo.lake WHERE @section='$'  )

GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_otherfish' AND xtype = 'FN')    DROP function dbo.fn_river_viewer_otherfish
GO 
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_fish' AND xtype = 'IF')    DROP function dbo.fn_river_viewer_fish
GO 
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_fish' AND xtype = 'IF') DROP function dbo.fn_river_fish
GO
/*
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_fish' AND xtype = 'IF')    DROP function dbo.fn_river_viewer_fish
GO 
*/
GO
/******
 * on page wfRiverViewer display list of fishes
 * depend on fn_river_viewer_otherfish
 *
 * INPUT PARAMETERS:
 *
 *    @@lake_id   uniqueidentifier  - a lake guid
 *    @length     INT               - minimal length of fish used for report
 *    @typeangler int               - type of angler. not used yet (reserved)
 *
 *  Usage: 
               SELECT * FROM dbo.fn_river_viewer_fish('AB45F146-1273-44D5-802F-D913EE0BB66F', 20, 0) ORDER BY today, fish_name DESC
 */
CREATE FUNCTION dbo.fn_river_viewer_fish( @guid varchar(64), @fish_max_length int = 20, @typeangler int = 0 )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
  WITH cte AS
  (
    SELECT fish_name, today
         , fish_id
         , ROW_NUMBER() OVER (ORDER BY x.fish_id) AS id
         , x.lake_id
      FROM
   (
        SELECT DISTINCT f.fish_name, f.fish_id, l.lake_id
        , CASE WHEN loc.today < 30 THEN 'Low' WHEN loc.today > 75  THEN 'High' ELSE 'Normal' END AS today  
            FROM dbo.fish_location loc 
            JOIN dbo.WaterStation ws ON loc.station_Id = ws.id
            JOIN dbo.fish f          ON f.fish_id  = loc.fish_id
            JOIN dbo.fish_zoo z          ON f.fish_id  = z.fish_id
            JOIN dbo.lake l          ON l.lake_id  = ws.lakeid 
            WHERE l.lake_id = CAST(@guid AS uniqueidentifier) AND  z.fish_max_length > 20 
    )x
  ) SELECT id, fish_name, today, link, CASE WHEN link Is NULL THEN 'empty.gif' ELSE 'link.png' END pic
          , cte.lake_id, cte.fish_id
      FROM cte 
      CROSS APPLY (SELECT TOP 1 fish_id, link FROM dbo.lake_fish lf WHERE cte.fish_id = lake_id AND @guid= fish_id ORDER BY link)lf
      WHERE cte.fish_id = lf.fish_id
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_fish' AND xtype = 'FN')    DROP function dbo.fn_river_viewer_fish
GO 
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_otherfish' AND xtype = 'FN')    DROP function dbo.fn_river_viewer_otherfish
GO 
/******
 * on page wfRiverViewer display list of other fishes not included to fn_river_viewer_fish
 * depend on fn_river_view
 *
 * INPUT PARAMETERS:
 *
 *    @@lake_id   uniqueidentifier  - a lake guid
 *    @typeangler int               - type of angler. not used yet (reserved)
 *
 *  Usage: 
               SELECT dbo.fn_river_viewer_otherfish('AB45F146-1273-44D5-802F-D913EE0BB66F', 0)
 */
CREATE FUNCTION dbo.fn_river_viewer_otherfish( @lake_id varchar(64), @typeangler int = 0 )
RETURNS nvarchar(2048)
WITH SCHEMABINDING
BEGIN
  DECLARE @result nvarchar(2048) = '';
  SELECT  @result = @result + '; ' + f.fish_name  FROM dbo.lake_fish l JOIN dbo.fish f ON l.fish_id = f.fish_id
    WHERE l.lake_id = @lake_id AND NOT EXISTS (SELECT fish_id FROM dbo.fn_river_viewer_fish( @lake_id, DEFAULT, @typeangler )x WHERE x.fish_id = l.fish_id)
    RETURN CASE WHEN NULLIF(@result, '') IS NULL THEN NULL ELSE  RIGHT(@result, LEN(@result)-1 ) END;
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
/*
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_otherfish' AND xtype = 'FN') DROP function dbo.fn_river_viewer_otherfish
GO 
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_viewer_fish' AND xtype = 'IF') DROP function dbo.fn_river_viewer_fish
GO 
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_fish' AND xtype = 'IF') DROP function dbo.fn_river_fish
GO
*/
--- returns firt fish from river having link
--    SELECT * FROM dbo.fn_river_fish('D07EFE63-BAF4-4DD1-9B1C-FE94C5860185', '1D55814F-8047-48A8-8915-F8823A2D20B6')
CREATE FUNCTION dbo.fn_river_fish( @fish_id uniqueidentifier, @lake_id uniqueidentifier )
RETURNS TABLE
WITH SCHEMABINDING
RETURN
   SELECT TOP 1 fish_id, link FROM dbo.lake_fish lf WHERE @lake_id = lake_id AND @fish_id  = fish_id ORDER BY link;
GO
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_resource_state' AND xtype = 'IF')
    DROP function dbo.fn_resource_state
GO 

-- used in RiverList in combobox
-- SELECT * FROM dbo.fn_resource_state( 'CA' )
create FUNCTION dbo.fn_resource_state( @country char(2) )
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
   SELECT DISTINCT s.state AS Value FROM dbo.lake l 
        JOIN dbo.Tributaries m ON l.lake_id=m.lake_id AND l.lake_id=m.Main_Lake_id AND m.side IN (16,32)
        JOIN dbo.states s ON m.state = s.state
      WHERE m.country IS NOT NULL AND DATALENGTH(m.country) = 2 
        AND m.state IS NOT NULL AND DATALENGTH(m.country) = 2 AND @country = m.country
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_view_fishing' AND xtype = 'IF')
    DROP function dbo.fn_river_view_fishing
GO

--   required for wfRiverRegulations to dispay river/lake
--    select * from dbo.fn_river_view_fishing('a6c730df-2892-e811-9104-00155d007b12')
create FUNCTION dbo.fn_river_view_fishing( @lake_id uniqueidentifier )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
    SELECT stateCountry, z.lake_id
         , CASE WHEN z.City IS NOT NULL AND DATALENGTH(z.City) > 0 THEN z.City + '&nbsp;twp.' ELSE '' END 
         + CASE WHEN z.County IS NOT NULL AND DATALENGTH(z.County) > 0 THEN ',&nbsp;' + ISNULL(z.County, '') ELSE '' END 
         + CASE WHEN z.Region IS NOT NULL AND DATALENGTH(z.Region) > 0 THEN ',&nbsp;' + ISNULL(z.Region, '') ELSE '' END 
         + CASE WHEN z.municipality IS NOT NULL AND DATALENGTH(z.municipality) > 0 THEN ',&nbsp;' + ISNULL(z.municipality, '') ELSE '' END 
         + CASE WHEN z.district IS NOT NULL AND DATALENGTH(z.district) > 0 THEN ', &nbsp;' + ISNULL(z.district, '') ELSE '' END 
         AS [description]
         , CASE WHEN z.link IS NULL THEN z.lake_name ELSE '<a href="' + z.link + '">' + z.lake_name + '</a>' END AS lake_name
         , z.alt_Name,  z.county,  z.state, z.country
         , CASE WHEN z.location IS NOT NULL THEN '<hr><table><tr><td>' + z.location + '</td></tr></table>' ELSE NULL END AS location
         , stateRules, stateName, stateParkRules, stateResidentFee, stateNonResidentFee

         , CASE WHEN z.regulations IS NOT NULL THEN '<tr><td><b>Exceptions to Regulations:</b></td><td><font color="red">' + z.regulations END + '</font>'
           + CASE WHEN z.link_reg IS NOT NULL THEN '&nbsp<a href="' + z.link_reg + '"><img src="/Images/link.png" /></a>' ELSE '' END
           + '</td></tr>' AS regulations
         , CASE WHEN z.zone IS NOT NULL THEN '<tr><td><b>Zone:</b></td><td>' + CAST(z.zone AS varchar(24)) + '</td></tr>' END AS zone 
      FROM
      (
        SELECT ('[' + t.state + '] ' + t.country) AS stateCountry
            ,  x.lake_id, lake_name,  alt_Name,  ISNULL(t.city, '') AS city
            , ISNULL(t.county, '') AS county
            , ISNULL(t.region, '') AS region
            , ISNULL(t.district, '') AS district, ISNULL(t.municipality, '') AS municipality
            , t.state, t.country
            , s.rules as stateRules, s.name as stateName
            , resident_fee as stateResidentFee, non_resident_fee as stateNonResidentFee, park_rules as stateParkRules
            , locType, t.[location]
            , link, watershield, t.zone, regulations, link_reg
            FROM dbo.lake x 
            JOIN dbo.Tributaries t ON x.lake_id=t.lake_id AND t.Main_Lake_id=x.lake_id
            JOIN dbo.states s ON t.state = s.state
            WHERE x.lake_id = @lake_id AND t.side=16
      )z 
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_view_regulations' AND xtype = 'IF')
    DROP function dbo.fn_river_view_regulations
GO
--   required for wfRiverRegulations to dispay river/lake
--    select * from dbo.fn_river_view_regulations('B74DCDFC-CC78-4464-BFB0-C64542A7DFF4')
create FUNCTION dbo.fn_river_view_regulations( @lake_id uniqueidentifier )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
    SELECT stateCountry, z.lake_id
         , CASE WHEN z.City IS NOT NULL AND DATALENGTH(z.City) > 0 THEN z.City + '&nbsp;twp.' ELSE '' END 
         + CASE WHEN z.County IS NOT NULL AND DATALENGTH(z.County) > 0 THEN ',&nbsp;' + ISNULL(z.County, '') ELSE '' END 
          + CASE WHEN z.municipality IS NOT NULL AND DATALENGTH(z.municipality) > 0 THEN ',&nbsp;' + ISNULL(z.municipality, '') ELSE '' END 
         + CASE WHEN z.district IS NOT NULL AND DATALENGTH(z.district) > 0 THEN ', &nbsp;' + ISNULL(z.district, '') ELSE '' END 
         AS [description]
         , CASE WHEN z.link IS NULL THEN z.lake_name ELSE '<a href="' + z.link + '">' + z.lake_name + '</a>' END AS lake_name
         , z.alt_Name,  z.county,  z.state, z.country
         , CASE WHEN z.location IS NOT NULL THEN '<hr><table><tr><td>' + z.location + '</td></tr></table>' ELSE NULL END AS location
         , stateRules, stateName, stateParkRules, stateResidentFee, stateNonResidentFee

         , CASE WHEN z.regulations IS NOT NULL THEN '<tr><td><b>Exceptions to Regulations:</b></td><td><font color="red">' + z.regulations END + '</font>'
           + CASE WHEN z.link_reg IS NOT NULL THEN '&nbsp<a href="' + z.link_reg + '"><img src="/Images/link.png" /></a>' ELSE '' END
           + '</td></tr>' AS regulations
         , CASE WHEN z.zone IS NOT NULL THEN '<tr><td><b>Zone:</b></td><td>' + CAST(z.zone AS varchar(24)) + '</td></tr>' END AS zone 
         , CASE WHEN r.lake_id IS NOT NULL THEN 1 ELSE 0 END AS IsException
      FROM
      (
        SELECT ('[' + t.state + '] ' + t.country) AS stateCountry
            ,  x.lake_id, lake_name,  alt_Name,  ISNULL(t.city, '') AS city
            , ISNULL(t.county, '') AS county
            , ISNULL(t.region, '') AS region
            , ISNULL(t.district, '') AS district, ISNULL(t.municipality, '') AS municipality
            , t.state, t.country
            , s.rules as stateRules, s.name as stateName
            , resident_fee as stateResidentFee, non_resident_fee as stateNonResidentFee, park_rules as stateParkRules
            , x.locType, t.[location]
            , x.link, x.watershield, t.zone, regulations, link_reg
            FROM dbo.lake x 
                JOIN dbo.Tributaries t ON x.lake_id=t.lake_id AND x.lake_id=t.Main_Lake_id
                JOIN dbo.states s ON t.state = s.state
            WHERE x.lake_id = @lake_id AND t.side=16
      )z LEFT JOIN dbo.regulations r ON r.lake_id = z.lake_id
         LEFT JOIN dbo.fish f ON r.fish_id = f.fish_id
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_location_trial' AND xtype = 'IF')
    DROP function dbo.fn_map_location_trial
GO
/****** Called from FishTracker.Forecast.MapFrame.LoadMapLocation
-- SELECT * FROM [dbo].[fn_get_trial_location]( 'burbot', 43, -80 )
-- SELECT * FROM [dbo].[fn_map_location_trial]( 'Bass, Rock', 43, -80 )
**/
CREATE function dbo.fn_map_location_trial( @fishName  varchar(64), @lat float, @lon float )
  RETURNS  TABLE
  WITH SCHEMABINDING
AS
RETURN   --lat, lon, today, location, sid, country, state, county
    SELECT w.lat,  w.lon,  f.today, w.LocName as location, w.sid, w.country, w.state, w.county
      FROM dbo.vWaterStation w JOIN dbo.fish_location f ON (f.station_Id = w.id  )
      WHERE ( w.lat between (@lat-3.0) AND (@lat+3.0) ) AND (w.lon between (@lon-3.0) AND (@lon+3.0) ) 
        AND EXISTS( SELECT TOP 1 1 FROM dbo.fish s WHERE fish_name = @fishName and f.fish_id = s.fish_id )
		AND EXISTS( SELECT TOP 1 1 FROM dbo.WaterData d WHERE d.mli = w.mli )
		/*
     UNION ALL
    select  spot_lat, spot_lon, 0, '', b.spot_sid, 'CA', 'ON', ''        -- also display fish spots
      FROM dbo.Spot a 
         LEFT JOIN dbo.fish_spot b ON a.spot_id = b.spot_id
      WHERE ( spot_lat between (@lat-3.0) AND (@lat+3.0) ) AND (spot_lon between (@lon-3.0) AND (@lon+3.0) )
        AND EXISTS( SELECT TOP 1 1 FROM dbo.fish s WHERE fish_name = @fishName and b.fish_id = s.fish_id ) */
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_location' AND xtype = 'IF')
    DROP function dbo.fn_map_location
GO

/****** Called from FishTracker.Forecast.MapFrame.LoadMapLocation
-- SELECT * FROM [fn_map_location]( 'Bass, rock', 43, -80, 'CA', 0 )
**/
CREATE function [dbo].[fn_map_location]( @fishName  varchar(64), @lat float, @lon float, @country char(3), @dist float )
  RETURNS  TABLE
  WITH SCHEMABINDING
AS
RETURN   --lat, lon, today, location, sid, country, state, county
    SELECT  w.lat, w.lon, f.today, w.LocName AS location, w.sid, w.country, w.state, w.county 
        FROM dbo.vWaterStation w
        JOIN dbo.fish_location f ON ( f.station_Id = w.id )
        JOIN dbo.fish          s ON ( f.fish_Id    = s.fish_Id )
        WHERE s.fish_name = @fishName AND @country = w.country
		AND EXISTS( SELECT TOP 1 1 FROM dbo.WaterData d WHERE d.mli = w.mli )
		/*
     UNION ALL
    select  spot_lat, spot_lon, 0, '', a.spot_sid, 'CA', 'ON', ''                -- also display fish spots
        FROM dbo.Spot a 
            LEFT JOIN dbo.fish_spot b ON a.spot_id = b.spot_id
        WHERE  EXISTS( SELECT TOP 1 1 FROM dbo.fish s WHERE fish_name = @fishName and b.fish_id = s.fish_id ) 
           OR  EXISTS( SELECT TOP 1 1 FROM dbo.fish f 
                         JOIN [dbo].lake_fish fl ON ( fl.fish_Id = f.fish_Id )
                         JOIN [dbo].lake l       ON ( fl.fish_Id = f.fish_Id )
                         JOIN [dbo].spot s       ON (  l.lake_Id = s.lake_Id AND s.spot_id = b.spot_id )
                         WHERE fish_name = @fishName and b.fish_id = f.fish_id ) 
						 */
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_fish_image_handler' AND xtype = 'FN')
    DROP function dbo.fn_fish_image_handler
GO

-- used in ~/Editor/HandlerImage.ashx
-- SELECT dbo.fn_fish_image_handler( '7a7fa636-9957-4287-9892-e2d003a006c3', 7 )
CREATE FUNCTION dbo.fn_fish_image_handler( @fish_id uniqueidentifier, @image_id int )
RETURNS varbinary(max) WITH SCHEMABINDING
BEGIN
    RETURN
        (SELECT TOP 1 fish_image_pic FROM 
            (
                SELECT fish_image_pic FROM dbo.fish_image WHERE fish_image_id = @image_id AND fish_id = @fish_id
                UNION ALL
                SELECT TOP 1 fish_image_pic FROM dbo.fish_image f WHERE EXISTS 
                ( SELECT fish_image_id FROM  (SELECT MAX(fish_image_id) AS fish_image_id FROM dbo.fish_image WHERE fish_id = @fish_id)x WHERE x.fish_image_id = f.fish_image_id)
            )y
        );
END
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_fish_image_info' AND xtype = 'IF')
    DROP function dbo.fn_fish_image_info
GO
-- used to display info about image
-- SELECT * from dbo.fn_fish_image_info( 'C2E8C307-F470-458B-8CEE-000999277126', 7 )
CREATE FUNCTION dbo.fn_fish_image_info( @fish_id uniqueidentifier, @image_id int )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
        (SELECT TOP 1 fish_image_gender, fish_image_source, fish_image_author, fish_image_link, fish_image_label, fish_image_location
                    , fish_image_lat, fish_image_lon, fish_image_tag, fish_image_stamp FROM 
            (
                SELECT fish_image_gender, fish_image_source, fish_image_author, fish_image_link, fish_image_label, fish_image_location
                     , fish_image_lat, fish_image_lon, fish_image_tag, fish_image_stamp FROM dbo.fish_image WHERE fish_image_id = @image_id AND fish_id = @fish_id
                UNION ALL
                SELECT fish_image_gender, fish_image_source, fish_image_author, fish_image_link, fish_image_label, fish_image_location
                     , fish_image_lat, fish_image_lon, fish_image_tag, fish_image_stamp FROM dbo.fish_image f WHERE EXISTS 
                ( SELECT fish_image_id FROM  (SELECT MAX(fish_image_id) AS fish_image_id FROM dbo.fish_image WHERE fish_id = @fish_id)x WHERE x.fish_image_id = f.fish_image_id)
            )y
        );
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_map_handler' AND xtype = 'FN')
    DROP function dbo.fn_lake_map_handler
GO
-- used in ~/Editor/HandlerImage.ashx to serve one attached map/document by id for its owner
-- SELECT dbo.fn_lake_map_handler( 'fc0d917b-d053-11d8-92e2-080020a0f4c9', 7 )
CREATE FUNCTION dbo.fn_lake_map_handler( @owner uniqueidentifier, @map_id int )
RETURNS varbinary(max) WITH SCHEMABINDING
BEGIN
    RETURN
        (SELECT TOP 1 lake_map_pic FROM dbo.lake_map
            WHERE lake_map_id = @map_id AND lake_map_ownerid = @owner);
END
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_map_list' AND xtype = 'IF')
    DROP function dbo.fn_lake_map_list
GO
-- used in ~/Editor/LakeMap.aspx to list every map/document/link attached to a water body
-- SELECT * FROM dbo.fn_lake_map_list( 'fc0d917b-d053-11d8-92e2-080020a0f4c9' )
CREATE FUNCTION dbo.fn_lake_map_list( @owner uniqueidentifier )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
        (SELECT lake_map_id, lake_map_type, lake_map_kind, lake_map_source, lake_map_author,
                lake_map_link, lake_map_label, lake_map_stamp
         FROM dbo.lake_map
         WHERE lake_map_ownerid = @owner);
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_fish_document' AND xtype = 'IF')
    DROP function dbo.fn_fish_document
GO
-- The single PDF document attached to a fish species (one row per fish, or empty when none).
-- Used by ~/Editor/FishEditor.aspx and ~/Resources/wfFishViewer.aspx to show a download link,
-- and by ~/Editor/HandlerImage.ashx (?fishdoc=) to stream the bytes. Callers that only need the
-- label/existence select those columns; the handler selects fish_document_pic (inline TVF, so the
-- blob is not materialized unless requested).
-- SELECT fish_document_id, fish_document_label, fish_document_stamp FROM dbo.fn_fish_document( '58FC0EFC-3728-4A7E-9622-43C9747078E8' )
CREATE FUNCTION dbo.fn_fish_document( @fish_id uniqueidentifier )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
        (SELECT fish_document_id, fish_document_label, fish_document_stamp, fish_document_pic
         FROM dbo.fish_document
         WHERE fish_id = @fish_id);
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_fish_spawn' AND xtype = 'IF')
    DROP function dbo.fn_fish_spawn
GO
-- used to display info about image
-- SELECT * FROM dbo.fn_fish_spawn( '58FC0EFC-3728-4A7E-9622-43C9747078E8' )
CREATE FUNCTION dbo.fn_fish_spawn( @fish_id uniqueidentifier  )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
    SELECT fish_spawn_stamp, fish_spawn_age_female, fish_spawn_age_male, fish_spawn_eggs_min, fish_spawn_eggs_max
         , fish_spawn_description, fish_spawn_location, reproductive_strategy FROM dbo.fish_spawn WHERE fish_Id = @fish_id
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_fish_list_bylatlon' AND xtype = 'IF')
    DROP function dbo.fn_map_fish_list_bylatlon
GO
-- Called from  FishTracker.Forecast.MapFrame.LoadInitialFishes
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon( 32, -117, 'US', 3   )
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon( 50, -95, 'CA', 3   )
CREATE FUNCTION dbo.fn_map_fish_list_bylatlon( @lat real, @lon real, @country char(2), @dist real  )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT v.fish_id, v.fish_name FROM dbo.fish v
    LEFT JOIN dbo.fish_zoo z ON z.fish_id = v.fish_id
    WHERE ( v.fish_Type & 1 ) = 1 -- 1 - sport fish
--	AND v.habitat = 1             -- 1 - freshwater
    AND EXISTS         -- 1 - sport fish
    ( 
		SELECT TOP 1 1 FROM dbo.fish_location f 
			JOIN dbo.WaterStation w ON (f.station_Id = w.id)
			WHERE f.fish_id = v.fish_id AND w.country = @country
			AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
			AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
    ) AND z.fish_max_length > 25      
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_fish_list_bylatlon_trial' AND xtype = 'IF')
    DROP function dbo.fn_map_fish_list_bylatlon_trial
GO
-- Called from  FishTracker.Forecast.MapFrame.LoadInitialFishes
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon_trial( 32, -117, 'US'   )
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon_trial( 50, -95, 'CA'   )
CREATE FUNCTION dbo.fn_map_fish_list_bylatlon_trial( @lat real, @lon real, @country char(2) )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT v.fish_id, v.fish_name FROM dbo.fish v
    LEFT JOIN dbo.fish_zoo z ON z.fish_id = v.fish_id
    WHERE ( v.fish_Type & 1 ) = 1 -- 1 - sport fish
--	AND v.habitat = 1             -- 1 - freshwater
    AND EXISTS
    ( 
		SELECT TOP 1 1 FROM dbo.fish_location f 
			JOIN dbo.WaterStation w ON (f.station_Id = w.id)
			WHERE f.fish_id = v.fish_id AND w.country = @country
--			AND ( w.lat between (@lat-0.5) AND (@lat+0.5) )
--			AND ( w.lon between (@lon-0.5) AND (@lon+0.5) )
    ) AND z.fish_max_length < 65
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_read_fish_edit_list' AND xtype = 'TF')
    DROP function dbo.fn_read_fish_edit_list
GO
-- used in FishTracker.TFishEditor.LoadUnEditedFish()
-- 1 - sport, 2 - Coarse, 4 - commersial, 8 - invading
-- select * from dbo.fn_read_fish_edit_list() where fish_id = '6b45fea3-5cbe-4982-89af-c241eb5c6a36'  ORDER BY fish_name ASC
CREATE FUNCTION [dbo].[fn_read_fish_edit_list]()
RETURNS @TBL TABLE ( fish_id uniqueidentifier, fish_name varchar(32), fish_latin varchar(64), synonims varchar(255) 
         , food_Type int, water_type int, feedsOver int, habitat int
         , tuLD float, tuL float, tuC float, tuH float, tuHD float 
         , tmLD float, tmL float, tmC float, tmH float, tmHD float
         , oxLD float, oxL float, oxC float, oxH float, oxHD float
         , phLD float, phL float, phC float, phH float, phHD float
         , veL float, veH float
         , depthMin float, depthMax float
         , saltL float, saltH float
         , NitrateH float, NitrateL float, PhosphateH float, PhosphateL float
         , HardnessL float, HardnessH float
         , periodStart int, periodEnd int, editor varchar(128), locked bit
         , fish_Type int, fish_ability int, react_color int, home_range float, distribution_area nvarchar(500), stamp datetime )
WITH SCHEMABINDING
AS
begin
  INSERT INTO @TBL ( fish_id, fish_name, fish_latin, synonims, food_Type
                   , water_type, fish_Type, fish_ability, react_color, home_range, distribution_area, stamp )
        SELECT fish_id, fish_name, fish_latin, alt_Name, food_Type, water_type, fish_Type
        , fish_ability, react_color, fish_home_range, fish_distribution_area, stamp FROM dbo.fish;

  update t SET t.depthMin = n.ri_min, t.depthMax = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 3 

  update t SET t.veL = n.ri_min, t.veH = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 41

  update t SET t.saltL = n.ri_min, t.saltH = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 49

  update t SET t.PhosphateL = n.ri_min, t.PhosphateH = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 57

  update t SET t.NitrateL = n.ri_min, t.NitrateH = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 65

  update t SET t.HardnessL = n.ri_min, t.HardnessH = n.ri_max 
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 73

  update t SET t.oxLD=n.ri_min, t.oxL=n.ri_low, t.oxC=n.ri_avg, t.oxH=n.ri_high, t.oxHD=n.ri_max
      from dbo.real_interval n RIGHT JOIN dbo.fish_Rule c ON c.id = n.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 33
  
  update t SET t.phLD=ph.ri_min, t.phL=ph.ri_low, t.phC=ph.ri_avg, t.phH=ph.ri_high, t.phHD=ph.ri_max
      from dbo.real_interval ph RIGHT JOIN dbo.fish_Rule c ON c.id = ph.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 9

  update t SET t.tmLD=tm.ri_min, t.tmL=tm.ri_low, t.tmC=tm.ri_avg, t.tmH=tm.ri_high, t.tmHD=tm.ri_max
      from dbo.real_interval tm RIGHT JOIN dbo.fish_Rule c ON c.id = tm.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 17

  update t SET t.tuLD=tu.ri_min, t.tuL=tu.ri_low, t.tuC=tu.ri_avg, t.tuH=tu.ri_high, t.tuHD=tu.ri_max
      from dbo.real_interval tu RIGHT JOIN dbo.fish_Rule c ON c.id = tu.ri_parent_id RIGHT JOIN @tbl t on t.fish_id=c.fish_id  
        WHERE c.periodStart=-1 AND c.periodEnd=-1 AND ri_type = 25
     
  update t SET t.locked = c.locked, t.feedsOver=c.feedsOver, t.habitat=c.habitat, t.editor = c.editor
     FROM @TBL t JOIN dbo.fish_Rule c ON t.fish_id=c.fish_id WHERE -1 = c.periodStart AND -1 = c.periodEnd
  return
end
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_edit_fish_general' AND xtype = 'IF')
    DROP function dbo.fn_edit_fish_general
GO

-- Called from  FishTracker.Editor.FishGeneral.LoadGeneralFish  and  FishTracker.Resources.wfFishViewer.LoadGeneral
-- SELECT * FROM [dbo].fn_edit_fish_general('a85ebf22-4ab9-4a91-a14a-cef6c8e64d97')
-- Image id must match what the editor tabs (Habitat/Zoology) show: the current picture is
-- dbo.fish_zoo.fish_zoo_image, which sp_add_fish_image repoints on every upload. fish_image_stamp
-- is a USER-ENTERED date (not upload order), so it must NOT drive "which is the latest image";
-- fall back to the newest fish_image by identity (insert order) only when no fish_zoo_image is set.
CREATE FUNCTION [dbo].fn_edit_fish_general( @fish_id varchar(36) )
RETURNS TABLE
WITH SCHEMABINDING
AS
  RETURN
    SELECT TOP 1 fish_latin, fish_name, alt_name AS fish_alt_name, descrip AS fish_description, uses AS fish_uses
        , ISNULL(locked, CONVERT(bit, 0)) AS locked, stamp, (select userName from dbo.users where id=editor) AS editor
        , fish_distribution_area
        , COALESCE(
              (SELECT TOP 1 fish_zoo_image FROM dbo.fish_zoo  WHERE fish_id = @fish_id AND fish_zoo_image IS NOT NULL),
              (SELECT TOP 1 fish_image_id  FROM dbo.fish_image WHERE fish_id = @fish_id ORDER BY fish_image_id DESC)
          ) AS fish_image_id
      FROM dbo.fish f WHERE f.fish_id = @fish_id
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_cvt_date2bigint' AND xtype = 'FN')
    DROP function dbo.fn_cvt_date2bigint
GO

CREATE function dbo.fn_cvt_date2bigint(@dt datetime2)
returns bigint
WITH SCHEMABINDING
as
begin
    RETURN CAST(convert(varchar(8), @dt, 112) AS BIGINT)*10000 + DATEPART(hour,@dt)*100+DATEPART(minute,@dt)  
end
GO
----------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_getfirstmlifish' AND xtype = 'IF')
    DROP function dbo.fn_getfirstmlifish
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_getfirstmlifish('05ME009');
-- SELECT CAST(fish_id AS varchar(36)), fish_name, fish_latin FROM dbo.fn_getfirstmlifish('05MD011')
CREATE function dbo.fn_getfirstmlifish(@mli varchar(64))
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    WITH cte AS
    ( 
        SELECT TOP 1 fish_id, w.mli FROM dbo.lake_fish fl 
			JOIN dbo.lake l ON l.lake_id = fl.lake_id 
			JOIN dbo.WaterStation w ON w.lakeid = l.lake_id 
			WHERE w.mli = @mli
			ORDER BY fl.stamp DESC
    )
	SELECT fish_id, fish_name, fish_latin FROM dbo.fish WHERE fish_id IN (SELECT fish_id FROM cte)
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_EditLakeLink' AND xtype = 'IF')
    DROP function dbo.fn_EditLakeLink
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_EditLakeLink('45c0706e-d3aa-47eb-80b1-3f4712817916', 16);
CREATE function dbo.fn_EditLakeLink(@lake uniqueidentifier, @type int)
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT TOP 1 lake_name, tname, lake_id, t_id, side, zone, country, county, state, city, elevation, location, descript, district, municipality, region, lat, lon 
FROM (
    SELECT 1 AS code, m.lake_name, l.lake_name AS tname, l.lake_id, m.lake_id AS t_id, t.side, t.zone, t.country, t.county, t.state, t.city, t.elevation, t.location, t.descript, t.district, t.municipality, t.region, t.lat, t.lon
        FROM dbo.lake l 
            JOIN dbo.Tributaries t ON l.lake_id = t.main_lake_id AND t.lake_id <> t.main_lake_id 
            JOIN dbo.lake m ON m.lake_id = t.lake_id 
        WHERE l.lake_id=@lake AND side = @type
    UNION 
    SELECT 2, l.lake_name, l.lake_name AS tname, l.lake_id, l.lake_id AS t_id, t.side, t.zone, t.country, t.county, t.state, t.city, t.elevation, t.location, t.descript, t.district, t.municipality, t.region, t.lat, t.lon
        FROM dbo.lake l 
            JOIN dbo.Tributaries t ON l.lake_id = t.main_lake_id AND t.lake_id = t.main_lake_id 
        WHERE l.lake_id=@lake AND side = @type
)x ORDER BY code
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_EditTributary' AND xtype = 'IF')
    DROP function dbo.fn_EditTributary
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_EditTributary('C0A2F9E8-1BC5-4431-9ED3-FAACF857E6EC');
CREATE function dbo.fn_EditTributary(@lake uniqueidentifier)
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT ROW_NUMBER() OVER (ORDER BY  lake_name ASC) AS num, lake_name, Lake_id, side, country, state, zone, id, lat, lon
    FROM
    (
        SELECT v.lake_name, t.Lake_id, side, t.country, t.state, t.zone, t.id, t.lat, t.lon
            FROM dbo.Tributaries t
                JOIN dbo.Lake l ON l.lake_id = t.Main_Lake_id JOIN dbo.Lake v ON v.lake_id = t.Lake_id
                WHERE Main_Lake_id = @lake AND side NOT IN (16, 32) 
                   OR ( t.Lake_id = @lake AND t.side = 1) 
                   OR ( t.Lake_id = @lake AND t.side in (4,8))
    )x
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_SubTributary' AND xtype = 'IF')
    DROP function dbo.fn_SubTributary
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_SubTributary('C0A2F9E8-1BC5-4431-9ED3-FAACF857E6EC');
CREATE function dbo.fn_SubTributary(@lake uniqueidentifier)
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT ROW_NUMBER() OVER (ORDER BY  lake_name ASC) AS num, lake_name, Lake_id, side, country, state, zone, id, lat, lon
    FROM
    (
        SELECT l.lake_name, l.Lake_id, side, t.country, t.state, t.zone, t.id, t.lat, t.lon
            FROM dbo.Tributaries t
                JOIN dbo.Lake l ON l.lake_id = t.main_Lake_id
                WHERE t.Lake_id = @lake AND side IN (16, 32, (16 | 1), (16 | 2), (32 | 1), (32 | 2))
    )x
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_EditLakeFish' AND xtype IN ('IF', 'TF'))
    DROP function dbo.fn_EditLakeFish
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_EditLakeFish('fc0d917b-d053-11d8-92e2-080020a0f4c9');
CREATE function dbo.fn_EditLakeFish(@lake uniqueidentifier)
RETURNS @TBL TABLE ( sid int not null primary key, fish_name sysname, fish_id uniqueidentifier, link nvarchar(2048), source_type int, type int )
WITH SCHEMABINDING
AS
BEGIN
    INSERT INTO @tbl
    SELECT t.sid, fish_name, t.fish_id, t.link, probability_source_type, null
        FROM dbo.lake_fish  t
        JOIN dbo.Lake l ON l.lake_id = t.Lake_id 
            JOIN dbo.fish v ON v.fish_id = t.fish_id
            JOIN dbo.fish_zoo z ON v.fish_id = z.fish_id
        WHERE t.Lake_id = @lake;
    -- select highest priority
    ;WITH cte AS 
    (
        SELECT fish_id, MAX(source_type) AS source_type FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
        DELETE FROM @tbl WHERE sid IN 
            ( SELECT MAX(sid) FROM ( SELECT t.sid, t.fish_id FROM cte JOIN @tbl t 
				ON t.fish_id = cte.fish_id AND t.source_type=cte.source_type )z GROUP BY fish_id HAVING COUNT(*) = 1 );
    -- remove duplicates with empty link
    ;WITH cte AS
    (
        SELECT fish_id FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
    DELETE FROM @tbl WHERE sid IN 
    ( SELECT t.sid FROM cte JOIN @tbl t ON t.fish_id = cte.fish_id WHERE link IS NULL );

    UPDATE t SET type = fish_type FROM @TBL t JOIN dbo.fish ON t.fish_id = fish.fish_id
    RETURN;        
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetCloseLake' AND xtype = 'IF')
    DROP function dbo.fn_GetCloseLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetLakeRegulations' AND xtype = 'IF')
    DROP function dbo.fn_GetLakeRegulations
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeZones' AND xtype = 'IF')
    DROP function dbo.fn_GetAllLakeZones
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeStates' AND xtype = 'IF')
    DROP function dbo.fn_GetAllLakeStates
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_ViewTributary' AND xtype = 'TF')
    DROP function dbo.fn_ViewTributary
GO
-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_ViewTributary('a6c730df-2892-e811-9104-00155d007b12', 0, 256);
--     SELECT * FROM dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000', 0, 256);
--     SELECT * FROM dbo.fn_ViewTributary('0c55ba0c-849c-20c3-9b46-02ad5bdf9847', 0, 256);
-- used in wfRiverViewer : LoadTributary(Guid lakeid)

CREATE function dbo.fn_ViewTributary( @lake uniqueidentifier, @istrial int, @rowcount int )
  RETURNS @TBL TABLE (num int not null, lake_name sysname, locType int, Lake_id uniqueidentifier, way varchar(36)
    , closest int, reviewed int
    , lat float, lon float, nrows int not null, source_district nvarchar(255), mouth_district nvarchar(255)
    , source_country char(2), mouth_country char(2), source_state nvarchar(64), mouth_state nvarchar(64), source_zone int, mouth_zone int)
WITH SCHEMABINDING
AS
BEGIN
	;WITH cte AS
	(
		SELECT ROW_NUMBER() OVER (ORDER BY  y.Lake_id ASC) AS num, y.Lake_id, y.side, y.coast, y.type, v.source_id, v.mouth_id  FROM
		(
			SELECT  Lake_id, side, NULL AS coast, 0 AS type FROM dbo.Tributaries t WHERE  t.Main_Lake_id = @lake 
			UNION ALL
			SELECT  Main_Lake_id, CASE WHEN side = 32 THEN 16 WHEN side=16 THEN 32 ELSE side END, coast, 1 AS type 
                FROM dbo.Tributaries t WHERE t.Lake_id = @lake 
		)y, dbo.vw_lake v WHERE v.lake_id = @lake
	)
    INSERT INTO @TBL
	SELECT num, lake_name, locType, Lake_id, way, 0 as closest, 0 as reviewed, lat, lon, nrows, source_district, mouth_district
	 , source_country, mouth_country, source_state, mouth_state, source_zone, mouth_zone FROM
	(
		SELECT num, m.lake_name, m.locType, m.Lake_id, way
		, CASE WHEN way = 'Outflow' THEN  m.source_lat ELSE m.mouth_lat END AS lat
		, CASE WHEN way = 'Outflow' THEN  m.source_lon ELSE m.mouth_lon END AS lon
		, COUNT(*) OVER () as nrows
		  , m.source_district, m.mouth_district, m.source_country, m.mouth_country, m.source_state, m.mouth_state, m.source_zone, m.mouth_zone
		FROM 
		(
			SELECT ROW_NUMBER() OVER (ORDER BY  lake_name ASC) AS num, lake_name, Lake_id, way
				FROM
				(
					SELECT DISTINCT t.Lake_id, lake_name
					, CASE WHEN side = 16 THEN CASE WHEN source_id <> t.Lake_id then 'Inflow' ELSE 'Source' END
						   WHEN side = 32 THEN CASE WHEN mouth_id  <> t.Lake_id then 'Outflow'ELSE 'Mouth' END
						   WHEN side = 16 AND coast = 'L'   then 'Left' 
						   WHEN side = 16 AND coast = 'R'   then 'Right' 
						   WHEN side = 1  then 'Linked'
						   WHEN  side = 4 then 'Inflow' 
						   WHEN  side = 8 then 'Outflow' 
						   WHEN  side = 2 then 'Throw' 
						   END as way 
					FROM 
					(
						SELECT num, Lake_id, side, coast, type, source_id, mouth_id FROM cte WHERE num IN
							(
							   SELECT num FROM cte
								EXCEPT
							   SELECT num FROM cte WHERE side IN (16, 32) AND lake_id IN ( SELECT lake_id FROM cte GROUP BY lake_id HAVING COUNT(*) = 3 )
							) AND Lake_id <> @lake
					)t
					 JOIN dbo.Lake l ON t.Lake_id = l.Lake_id  
					 WHERE t.Lake_id <> @lake
				)x WHERE way IS NOT NULL
		)y JOIN dbo.vw_lake m ON m.lake_id = y.lake_id
	)q  WHERE  @isTrial = 1 AND locType <> 64 AND nrows > 20 
        OR @isTrial = 1 AND nrows <= 20 
	    OR (@isTrial = 0)
    RETURN
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_EditLakeFish' AND xtype = 'TF')
    DROP function dbo.fn_EditLakeFish
GO

-- get fish for station science view related or any first
--     SELECT * FROM dbo.fn_EditLakeFish('fcdf62d3-f1b3-4715-bfca-78dcf0e3a4c5');
CREATE function dbo.fn_EditLakeFish(@lake uniqueidentifier)
RETURNS @TBL TABLE ( sid int not null primary key, fish_name sysname, fish_id uniqueidentifier, link nvarchar(2048), source_type int, status tinyint )
WITH SCHEMABINDING
AS
BEGIN
    INSERT INTO @tbl
    SELECT t.sid, fish_name, t.fish_id, t.link, probability_source_type, t.status
        FROM dbo.lake_fish  t
        JOIN dbo.Lake l ON l.lake_id = t.Lake_id 
            JOIN dbo.fish v ON v.fish_id = t.fish_id
            JOIN dbo.fish_zoo z ON v.fish_id = z.fish_id
        WHERE t.Lake_id = @lake;
    -- select highest priority
    ;WITH cte AS 
    (
        SELECT fish_id, MAX(source_type) AS source_type FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
        DELETE FROM @tbl WHERE sid IN 
            ( SELECT MAX(sid) FROM ( SELECT t.sid, t.fish_id FROM cte JOIN @tbl t ON t.fish_id = cte.fish_id AND t.source_type=cte.source_type )z GROUP BY fish_id HAVING COUNT(*) = 1 );
    -- remove duplicates with empty link
    ;WITH cte AS
    (
        SELECT fish_id FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
    DELETE FROM @tbl WHERE sid IN 
    ( SELECT t.sid FROM cte JOIN @tbl t ON t.fish_id = cte.fish_id WHERE link IS NULL );
    RETURN;        
END
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_fish' AND xtype = 'FN')
    DROP function dbo.fn_lake_fish
GO


/******
 * get fish data related to lake
 * used for fish editor at lake/river
 *
 * Author: K.T.
 * INPUT PARAMETERS:
 *
 *    @lake uniqueidentifier        -- lake id
 *
 *    Usage:    
                SELECT dbo.fn_lake_fish('d3ddad1e-d054-11d8-92e2-080020a0f4c9');
 */
CREATE  function dbo.fn_lake_fish(@lake uniqueidentifier)
RETURNS XML
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @TBL TABLE (
      sid int not null primary key
    , fish_name sysname
    , fish_id uniqueidentifier
    , link nvarchar(2048)
    , source_type int
    , type int, last_catch date
    , status tinyint );

    INSERT INTO @tbl
    SELECT t.sid, fish_name, t.fish_id, t.link, probability_source_type, null, CAST(t.last_catch AS DATE), t.status
        FROM dbo.lake_fish  t
        JOIN dbo.Lake l ON l.lake_id = t.Lake_id 
            JOIN dbo.fish v ON v.fish_id = t.fish_id
            JOIN dbo.fish_zoo z ON v.fish_id = z.fish_id
        WHERE t.Lake_id = @lake;
    -- select highest priority
    ;WITH cte AS 
    (
        SELECT fish_id, MAX(source_type) AS source_type FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
        DELETE FROM @tbl WHERE sid IN 
            ( SELECT MAX(sid) FROM ( SELECT t.sid, t.fish_id FROM cte JOIN @tbl t 
				ON t.fish_id = cte.fish_id AND t.source_type=cte.source_type )z GROUP BY fish_id HAVING COUNT(*) = 1 );
    -- remove duplicates with empty link
    ;WITH cte AS
    (
        SELECT fish_id FROM @tbl GROUP BY fish_id HAVING COUNT(*) > 1
    )
    DELETE FROM @tbl WHERE sid IN 
    ( SELECT t.sid FROM cte JOIN @tbl t ON t.fish_id = cte.fish_id WHERE link IS NULL );

    UPDATE t SET type = fish_type FROM @TBL t JOIN dbo.fish ON t.fish_id = fish.fish_id

    DECLARE @result XML =
    (SELECT noFish, is_fishing_prohibited, isFish, fishing, lake_name, Lake_id, Reviewed, 
        (SELECT sid, fish_name, fish_id, link, source_type, type, last_catch, status FROM @TBL [fish] ORDER BY fish_name ASC FOR XML AUTO, TYPE)
        FROM dbo.lake WHERE lake_id = @lake FOR XML AUTO); 

    RETURN @result;        
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_EditLakeHelpList' AND xtype = 'IF')
    DROP function dbo.fn_EditLakeHelpList
GO

-- gives suggested fished for LakeFish Editor
-- SELECT * FROM dbo.fn_EditLakeHelpList( '0c49aa05-849c-20c3-ed12-b67a8b7cc629' )
CREATE function dbo.fn_EditLakeHelpList( @lake uniqueidentifier )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT sid, f.fish_id, fish_name, l.created FROM 
(
    SELECT fish_id, created FROM 
    ( 
        SELECT TOP 100 fish_id, MAX(created) AS created FROM dbo.lake_fish WHERE lake_id <> @lake 
		    GROUP BY fish_id ORDER BY created DESC 
    ) x 
	WHERE NOT EXISTS (SELECT 1 FROM dbo.lake_fish l WHERE l.lake_Id =  @lake AND l.fish_id = x.fish_id)
)l JOIN dbo.fish f ON l.fish_id = f.fish_id 
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_DefaultLastLake' AND xtype = 'IF')
    DROP function dbo.fn_DefaultLastLake
GO

-- gives suggested fished for default page
-- SELECT * FROM dbo.fn_DefaultLastLake( 'CA' )
CREATE function dbo.fn_DefaultLastLake( @country char(2) )
  RETURNS TABLE 
AS
RETURN
    SELECT TOP 20 lake_id, lake_name, stamp, lat, lon FROM
    (
        SELECT TOP 5 l.lake_id, l.lake_name, l.stamp, s.lat , s.lon 
                FROM dbo.lake l 
                    JOIN dbo.Tributaries s ON s.main_lake_id = l.lake_id AND s.side = 16
                WHERE s.Lat IS NOT NULL AND s.Lon IS NOT NULL AND l.locType = 2 AND s.country = @country
				   AND EXISTS (SELECT 1 FROM lake_fish f WHERE l.lake_Id = f.lake_Id)
                ORDER BY l.stamp DESC
        UNION ALL
        SELECT TOP 5 l.lake_id, l.lake_name, l.stamp, s.lat , s.lon 
                FROM dbo.lake l
                    JOIN dbo.Tributaries s ON s.main_lake_id = l.lake_id AND s.side = 16
                WHERE s.Lat IS NOT NULL AND s.Lon IS NOT NULL AND l.locType = 1 AND s.country = @country
					AND EXISTS (SELECT 1 FROM lake_fish f WHERE l.lake_Id = f.lake_Id)
                ORDER BY l.stamp DESC
        UNION ALL
        SELECT TOP 5 l.lake_id, l.lake_name, l.stamp, s.lat , s.lon 
                FROM dbo.lake l
                    JOIN dbo.Tributaries s ON s.main_lake_id = l.lake_id AND s.side = 16
                    , dbo.vw_NewID n
                WHERE s.Lat IS NOT NULL AND s.Lon IS NOT NULL AND l.locType IN (1,2) AND s.country = @country
								   AND EXISTS (SELECT 1 FROM lake_fish f WHERE l.lake_Id = f.lake_Id)
                ORDER BY n.new_id
    )x ORDER BY lake_id
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_LocType' AND xtype = 'IF')
    DROP function dbo.fn_LocType
GO
/*
   display water types for river list for trial ar registred users
   -- gives suggested fished for LakeFish Editor
-- SELECT * FROM dbo.fn_LocType( 'CA', 0 )
*/
CREATE function dbo.fn_LocType( @country char(2), @trial bit )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT locType, CAST(COUNT(*) AS int) AS cnt FROM dbo.lake l where locType IN (1, 2 ) AND @trial = 1
	AND EXISTS (SELECT 1 FROM dbo.Tributaries t WHERE t.Main_Lake_id = l.lake_id AND country = @country) GROUP BY locType  
UNION ALL
SELECT locType, CAST(COUNT(*) AS int) AS cnt FROM  dbo.lake l where locType IN (1, 2, 4, 8, 32, 64, 128, 8192 ) AND @trial = 0
	AND EXISTS (SELECT 1 FROM dbo.Tributaries t WHERE t.Main_Lake_id = l.lake_id AND country = @country) GROUP BY locType  
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_ANSII2CODE' AND xtype = 'IF')
    DROP function dbo.fn_ANSII2CODE
GO
/*
	convert unicode symbols as list of codes
	Usage: SELECT * FROM dbo.fn_ANSII2CODE( N'preved medved')
	Execute result : as SELECT NCHAR(73)+NCHAR(110)+NCHAR(105)
*/
CREATE FUNCTION dbo.fn_ANSII2CODE( @value sysname )
RETURNS TABLE
AS
  RETURN 
	WITH cte AS
	( 
		select CAST(UNICODE(substring(a.b, v.number+1, 1)) AS varchar(16)) AS value from (select b FROM (VALUES (@value))x(b)) a 
			join master.dbo.spt_values v on v.number < len(a.b) where v.type = 'P'
	)
	SELECT 'NCHAR(' + (SELECT STRING_AGG(value, ')+NCHAR(') AS state_code FROM cte) + ')' AS value
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetCloseLake' AND xtype = 'IF')
    DROP function dbo.fn_GetCloseLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetCloseByLatLon' AND xtype = 'IF')
    DROP function dbo.GetCloseByLatLon
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetCloseByDistance' AND xtype = 'IF')
    DROP function dbo.GetCloseByDistance
GO
/*
    Get closetst lakes near point with a distance
    select top 15 lake_id, closest from dbo.GetCloseByDistance( 46.9187080460205, -82.2112350422363, 1)
 */
CREATE function GetCloseByDistance( @lat float, @lon float, @distance int)
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    select lake_id, main_lake_id, @distance as closest from dbo.Tributaries 
        where lat > 0 and lon < 0 
            and (lat > (@lat - (0.01 * @distance)) and lat < (@lat + (0.01 * @distance))) 
            and (lon < (@lon + (0.01 * @distance)) and lon > (@lon - (0.01 * @distance))) 
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetCloseLake' AND xtype = 'IF')
    DROP function dbo.fn_GetCloseLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetCloseByLatLon' AND xtype = 'IF')
    DROP function dbo.GetCloseByLatLon
GO
/*
    Get closetst lakes near point
    select top 15 lake_id, closest from dbo.GetCloseByLatLon( 46.9187080460205, -82.2112350422363 )
 */
CREATE function GetCloseByLatLon( @lat float, @lon float )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    select TOP 15 lake_id, MIN(closest) as closest from 
    (
        select top 15 lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 1)
        union 
        select top 15 main_lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 1)
        union all
        select top 15 lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 5)
        union 
        select top 15 main_lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 5)
        union all
        select top 15 lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 10)
        union 
        select top 15 main_lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 10)
        union all
        select top 15 lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 20)
        union 
        select top 15 main_lake_id, closest from dbo.GetCloseByDistance( @lat, @lon, 20)
    )x  group by lake_id ORDER BY closest ASC

GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetCloseLake' AND xtype = 'IF')
    DROP function dbo.fn_GetCloseLake
GO
/* 
 select * from dbo.fn_GetCloseLake( '0c5e1097-849c-20c3-04f0-7bdd1e0a5ee5' )
 Used in river view aspx page as close by rivers
 */
CREATE FUNCTION dbo.fn_GetCloseLake( @lakeId uniqueidentifier, @istrial int, @rowcount int )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    SELECT num, lake_id, lake_name, lat, lon, closest, locType, reviewed FROM
	(
		SELECT TOP 256 ROW_NUMBER() OVER (ORDER BY closest ASC) AS num, v.lake_id, v.lake_name, lat, lon, y.closest, locType
		, CASE WHEN v.reviewed IS NULL OR v.reviewed = 0 THEN 0 ELSE 1 END AS reviewed 
		FROM
		(
			SELECT x.lake_id, MIN(x.closest) AS closest FROM dbo.fn_ViewTributary(@lakeId, @istrial, @rowcount) cross apply  dbo.GetCloseByLatLon( lat, lon ) x 
				WHERE NOT EXISTS ( SELECT 1 FROM dbo.fn_ViewTributary(@lakeId, @isTrial, @rowcount) z WHERE x.lake_id = z.lake_id )
				group by x.lake_id
		)y JOIN dbo.vw_lake v ON v.lake_id = y.lake_id
		WHERE v.lake_id <> @lakeId 
	)z WHERE num <  @rowcount
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetLakeRegulations' AND xtype = 'IF')
    DROP function dbo.fn_GetLakeRegulations
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeStates' AND xtype = 'IF')
    DROP function dbo.fn_GetAllLakeStates
GO
/* 
 select * from dbo.fn_GetAllLakeStates( '0c369d7b-849c-20c3-6274-0fd28a9dbbf4' )
 select * FROM dbo.fn_ViewTributary('0c369d7b-849c-20c3-6274-0fd28a9dbbf4', 0)
 River may flow throw several states and counters, function retuns all of them
 */
CREATE FUNCTION dbo.fn_GetAllLakeStates( @lakeId uniqueidentifier )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    WITH cte ( country, state ) AS
    (
        SELECT source_country, source_state FROM dbo.fn_ViewTributary(@lakeId, 0, 256)
        UNION
        SELECT mouth_country, mouth_state FROM dbo.fn_ViewTributary(@lakeId, 0, 256)
    )SELECT DISTINCT country, state FROM cte WHERE  country IS NOT NULL OR state  IS NOT NULL
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetLakeRegulations' AND xtype = 'IF')
    DROP function dbo.fn_GetLakeRegulations
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeZones' AND xtype = 'IF')
    DROP function dbo.fn_GetAllLakeZones
GO
/* 
 select * from dbo.fn_GetAllLakeZones( '0c369d7b-849c-20c3-6274-0fd28a9dbbf4' )
 select * FROM dbo.fn_ViewTributary('0c369d7b-849c-20c3-6274-0fd28a9dbbf4', 0)
 River may flow throw several fishing zones
 */
CREATE FUNCTION dbo.fn_GetAllLakeZones( @lakeId uniqueidentifier )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    WITH cte ( zone_id ) AS
    (
        SELECT source_zone FROM dbo.fn_ViewTributary(@lakeId, 0, 256)
        UNION
        SELECT mouth_zone FROM dbo.fn_ViewTributary(@lakeId, 0, 256)
    )SELECT DISTINCT zone_id FROM cte WHERE zone_id IS NOT NULL
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetLakeRegulations' AND xtype = 'IF')
    DROP function dbo.fn_GetLakeRegulations
GO
/*
 select * from dbo.fn_GetLakeRegulations( '0c369d7b-849c-20c3-6274-0fd28a9dbbf4' )
 Each River has list of EFFECTIVE (visible) regulations for the water body.

 Resolution (see aspnet/Editor/REGULATIONS.md):
   subject = (fish_id, regulations_part, resident_type)
   1) Collect candidates at 3 levels:
        level 1  lake-specific  (Lake_id = @lake_id)
        level 2  zone-wide      (Lake_id NULL, zone in the lake's zones) -- fish rules gated by lake_fish
        level 3  state fallback (Lake_id NULL, zone_id NULL, state in the lake's states)
   2) Specificity: per subject keep the most specific level present (lake < zone < state).
   3) Year version: per subject keep only the newest reg_year (older years stay in the table
      as history but are NOT effective). Split-season rows of the winning year all survive.
 */
CREATE FUNCTION dbo.fn_GetLakeRegulations( @lake_id uniqueidentifier )
  RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    WITH candidates AS
    (
        -- level 1: lake-specific
        SELECT 1 AS level, r.regulations_id, r.regulations_part, r.state, r.zone_id, r.Lake_id, r.fish_id, r.chain, r.reg_year
             , r.regulations_date_start, r.regulations_start, r.regulations_date_end, r.regulations_end
             , r.regulations_sport, r.regulations_sport_text, r.regulations_consr, r.regulations_consr_text
             , r.possession_sport, r.possession_consr, r.min_length_cm, r.slot_min_cm, r.slot_max_cm
             , r.slot_over_limit, r.method_flags, r.resident_type, r.regulations_code, r.regulations_link, r.regulations_stamp, r.regulations_text
            FROM dbo.regulations r
            WHERE r.Lake_id = @lake_id
        UNION ALL
        -- level 2: zone-wide; a fish rule shows only if the fish is confirmed on this water body
        SELECT 2 AS level, r.regulations_id, r.regulations_part, r.state, r.zone_id, r.Lake_id, r.fish_id, r.chain, r.reg_year
             , r.regulations_date_start, r.regulations_start, r.regulations_date_end, r.regulations_end
             , r.regulations_sport, r.regulations_sport_text, r.regulations_consr, r.regulations_consr_text
             , r.possession_sport, r.possession_consr, r.min_length_cm, r.slot_min_cm, r.slot_max_cm
             , r.slot_over_limit, r.method_flags, r.resident_type, r.regulations_code, r.regulations_link, r.regulations_stamp, r.regulations_text
            FROM dbo.regulations r
            JOIN dbo.fn_GetAllLakeZones( @lake_id ) z ON r.zone_id = z.zone_id
            WHERE r.Lake_id IS NULL
              AND ( r.fish_id IS NULL
                    OR EXISTS ( SELECT 1 FROM dbo.lake_fish lf WHERE lf.lake_Id = @lake_id AND lf.fish_Id = r.fish_id ) )
        UNION ALL
        -- level 3: state fallback
        SELECT 3 AS level, r.regulations_id, r.regulations_part, r.state, r.zone_id, r.Lake_id, r.fish_id, r.chain, r.reg_year
             , r.regulations_date_start, r.regulations_start, r.regulations_date_end, r.regulations_end
             , r.regulations_sport, r.regulations_sport_text, r.regulations_consr, r.regulations_consr_text
             , r.possession_sport, r.possession_consr, r.min_length_cm, r.slot_min_cm, r.slot_max_cm
             , r.slot_over_limit, r.method_flags, r.resident_type, r.regulations_code, r.regulations_link, r.regulations_stamp, r.regulations_text
            FROM dbo.regulations r
            JOIN dbo.fn_GetAllLakeStates( @lake_id ) z ON r.state = z.state
            WHERE r.Lake_id IS NULL AND r.zone_id IS NULL
    ),
    -- keep, per subject, only rows at the most specific level present
    -- (SELECT * is disallowed under SCHEMABINDING, so columns are listed explicitly)
    best_level AS
    (
        SELECT c.level, c.regulations_id, c.regulations_part, c.state, c.zone_id, c.Lake_id, c.fish_id, c.chain, c.reg_year
             , c.regulations_date_start, c.regulations_start, c.regulations_date_end, c.regulations_end
             , c.regulations_sport, c.regulations_sport_text, c.regulations_consr, c.regulations_consr_text
             , c.possession_sport, c.possession_consr, c.min_length_cm, c.slot_min_cm, c.slot_max_cm
             , c.slot_over_limit, c.method_flags, c.resident_type, c.regulations_code, c.regulations_link, c.regulations_stamp, c.regulations_text
             , MIN(c.level) OVER ( PARTITION BY c.fish_id, c.regulations_part, c.resident_type ) AS lvl_keep
            FROM candidates c
    ),
    -- of those, keep only the newest year (older years remain in the table but are not effective)
    best_year AS
    (
        SELECT b.regulations_id, b.regulations_part, b.state, b.zone_id, b.Lake_id, b.fish_id, b.chain, b.reg_year
             , b.regulations_date_start, b.regulations_start, b.regulations_date_end, b.regulations_end
             , b.regulations_sport, b.regulations_sport_text, b.regulations_consr, b.regulations_consr_text
             , b.possession_sport, b.possession_consr, b.min_length_cm, b.slot_min_cm, b.slot_max_cm
             , b.slot_over_limit, b.method_flags, b.regulations_code, b.regulations_link, b.regulations_stamp, b.regulations_text
             , MAX(b.reg_year) OVER ( PARTITION BY b.fish_id, b.regulations_part, b.resident_type ) AS yr_keep
            FROM best_level b
            WHERE b.level = b.lvl_keep
    )
    SELECT regulations_id, regulations_part, state, zone_id, Lake_id, fish_id, chain, reg_year
         , regulations_date_start, regulations_start, regulations_date_end, regulations_end
         , regulations_sport, regulations_sport_text, regulations_consr, regulations_consr_text
         , possession_sport, possession_consr
         , min_length_cm, slot_min_cm, slot_max_cm, slot_over_limit, method_flags
         , regulations_code, regulations_link, regulations_stamp, regulations_text
        FROM best_year
        WHERE reg_year = yr_keep
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.types WHERE is_table_type = 1 AND name = 't_xmltype')
    DROP type t_xmltype
GO

CREATE TYPE t_xmltype AS TABLE (id int not null identity(1,1), name sysname UNIQUE, value varchar(255));
GO
-------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------- 
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_data2cdata' AND xtype = 'FN')
    DROP function dbo.fn_data2cdata ;
GO
/******
 * convert string to CDATA section
 *
 * INPUT PARAMETERS:
 *
 *    @root         sysname       -- node name
 *    @root         sysname       -- attribute name
 *    @root         sysname       -- attribute value
 *    @data         nvarchar(max) -- unicode data
 *
 *    Usage:    declare @v t_xmltype; insert into @v values ('name', 'test') ;
                SELECT dbo.fn_data2cdata(N'node', N'<test!>', @v) as val;
 */
CREATE function dbo.fn_data2cdata( @root sysname, @atrname sysname, @atrguid uniqueidentifier, @data nvarchar(max) )
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @rst nvarchar(max) = '';

    IF NULLIF(TRIM(@data), '') IS NOT NULL 
    BEGIN
        select @rst  = CAST(val As nvarchar(max)) from 
        (
            select * from 
            (
                SELECT 1 AS Tag, 0 AS Parent, null AS [Az-aZ!1], null AS [Az-aZ!2], null AS [Az-aZ!2!CDATA]
                UNION ALL
                SELECT 2, 1, null, null, @data
            ) t FOR XML EXPLICIT, BINARY BASE64
        )x(val);

        SET @rst = REPLACE( REPLACE( @rst, N'<Az-aZ/>', N''), N'<Az-aZ ',N'');
        SET @rst = REPLACE( @rst, N'<Az-aZ>', N'');
        SET @rst = REPLACE( @rst, N'CDATA="', N'<![CDATA[' );
        SET @rst = REPLACE( @rst, N'"/></Az-aZ>', N']]>');

        SET @rst = N'<' + @root + N' name="' + @atrname + N'"' 
        + CASE WHEN @atrguid IS NULL THEN N'' ELSE N' guid="' + CAST(@atrguid AS char(36)) + '"'  END
        + N'>' +  @rst + N'</' + @root + '>';
    END;

    RETURN @rst;
END
GO
 -- declare @v t_xmltype; insert into @v values ('name', 'test'), ('result', 'passed') ;
 -- SELECT dbo.fn_data2cdata(N'node', N'name', N'test', CAST(N'<test!>' AS varbinary(max))) as val;
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_xml_tributary' AND xtype = 'FN')
    DROP function dbo.fn_xml_tributary ;
GO
/*
SELECT * FROM dbo.fn_ViewTributary('0c417be9-849c-20c3-1acf-10a55233029a', 0)
SELECT dbo.fn_xml_tributary('fcb82e5c-9bc4-4179-a962-abf98c6c4fff', 1 )
SELECT doc FROM dbo.fn_lake_view_info('fcb82e5c-9bc4-4179-a962-abf98c6c4fff')
*/
CREATE function dbo.fn_xml_tributary(@lake_id uniqueidentifier, @header bit)
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @main nvarchar(max)
          , @source_district nvarchar(255)
          , @mouth_district nvarchar(255)
          , @lake_name nvarchar(128);

    ;WITH TributaryData AS
    (
        SELECT lake_id
             , way
             , FORMAT(CONVERT(float, lat), '0.############') AS lat  -- Convert to float before formatting
             , FORMAT(CONVERT(float, lon), '0.############') AS lon  -- Convert to float before formatting
             , source_country
             , mouth_country
             , REPLACE(lake_name, '''', '"') as lake_name
             , source_state
             , mouth_state
             , source_zone
             , mouth_zone
             , source_district
             , mouth_district
        FROM dbo.fn_ViewTributary(@lake_id, 0, 256)
    )
    SELECT @main = val, @source_district = source_district, @mouth_district = mouth_district
         , @lake_name = lake_name FROM
    (
        SELECT * FROM
        (
            SELECT lake_id, way, FORMAT(CONVERT(float, lat), '0.############') AS lat
                 , FORMAT(CONVERT(float, lon), '0.############') AS lon
                 , source_country, mouth_country, REPLACE(lake_name, '''', '"') as lake_name
                 , source_state, mouth_state, source_zone, mouth_zone
                 FROM TributaryData z
        ) t FOR XML RAW ('node')
    ) x(val), TributaryData y;

    RETURN CASE WHEN @header = 1 THEN '<?xml version="1.0"?><root>' ELSE '' END
        + COALESCE(@main, '')
        + dbo.fn_data2cdata(N'node', N'lake_name', null, @lake_name)
        + dbo.fn_data2cdata(N'node', N'source_district', null, @source_district)
        + dbo.fn_data2cdata(N'node', N'mouth_district', null, @mouth_district)
        + CASE WHEN @header = 1 THEN '</root>' ELSE '' END;
END;

GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_edit' AND xtype = 'FN')
    DROP function dbo.fn_lake_edit ;
GO
/******
 * get description data related to lake
 * used for lake editor
 *
 * INPUT PARAMETERS:
 *    @lake uniqueidentifier        -- lake id
 *
 *    Usage:    
                SELECT dbo.fn_lake_edit('982070AB-BBE4-11D8-92E2-080020A0F4C9')
                SELECT dbo.fn_lake_edit('29efd95b-c6be-11d8-92e2-080020a0f4c9');
                select * from lake where lake_id = '1EB8EABC-BE3C-11D8-92E2-080020A0F4C9'
                UPDATE lake SET isFish = 0 where lake_id = '1EB8EABC-BE3C-11D8-92E2-080020A0F4C9'
 */
CREATE function dbo.fn_lake_edit(@lake_id uniqueidentifier)
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @main nvarchar(max), @name sysname, @native nvarchar(255), @french_name nvarchar(255), @lake_road_access nvarchar(255)
        , @source_name nvarchar(255), @mouth_name nvarchar(255), @fish nvarchar(max), @descript nvarchar(max), @link nvarchar(2048)
        , @drainage nvarchar(128), @discharge nvarchar(128), @watershield nvarchar(128), @fishing nvarchar(max), @alt_name nvarchar(64)
        , @src_id uniqueidentifier, @mth_id uniqueidentifier
    ;WITH cte AS
    (
        SELECT l.lake_id, l.lake_name, l.alt_name, l.[native], l.french_name
        , l.stamp, l.locType, l.link, l.depth, l.width, l.length, l.volume
        , l.isFish, l.noFish, l.isolated, l.is_fishing_prohibited, l.sid, l.drainage, l.discharge, l.watershield, l.basin
        , l.surface, l.shoreline, l.lake_road_access, l.CGNDB, l.descript, l.fishing
        , w.source_name, w.mouth_name, w.source_state, w.source_country, l.source, l.mouth, l.reviewed
      FROM dbo.lake l JOIN dbo.vw_lake w ON l.lake_id=w.lake_id WHERE w.lake_id = @lake_id
    )
    SELECT @main = val, @name = lake_name, @native = [native], @french_name = french_name, @descript = descript
         , @lake_road_access = lake_road_access, @source_name = source_name, @mouth_name = mouth_name, @link = link
         , @drainage = drainage, @discharge = discharge, @watershield = watershield, @fishing = fishing, @alt_name = alt_name
         , @src_id = source, @mth_id = mouth
         FROM
    (
        SELECT * FROM
        (
            SELECT lake_id, stamp, locType, depth, width, length, volume, surface, shoreline, CGNDB, source_state, source_country
                 , COALESCE(isfish, 0) AS is_fish, COALESCE(noFish, 0) AS no_fish, lake_road_access
                 , COALESCE(is_fishing_prohibited, 0) AS is_fishing_prohibited, COALESCE(reviewed, 0) AS reviewed
                 , isolated, link, basin, sid, drainage, discharge, watershield, fishing, source, mouth
                 FROM cte
        ) t FOR XML RAW ('lake')
    ) x(val), cte;

    SELECT  @fish = COALESCE(val, '') FROM
    ( 
        SELECT * FROM
        (
            SELECT l.fish_id, fish_name FROM lake_fish l JOIN fish f  ON l.fish_id = f.fish_id WHERE lake_id = @lake_id
        ) t FOR XML RAW ('fish')
    ) x(val)

    DECLARE @vals nvarchar(max) = (SELECT STRING_AGG(mli, ',') FROM WaterStation WHERE lakeid=@lake_id);
    IF @vals IS NULL
    BEGIN
        SET @vals = '';
    END
    RETURN '<?xml version="1.0"?><root>' + @main
        + dbo.fn_data2cdata(N'node', N'lake_name',        null,     @name )        
        + dbo.fn_data2cdata(N'node', N'native',           null,     @native )
        + dbo.fn_data2cdata(N'node', N'french_name',      null,     @french_name ) 
        + dbo.fn_data2cdata(N'node', N'lake_road_access', null,     @lake_road_access )
        + dbo.fn_data2cdata(N'node', N'source_name',      @src_id,  @source_name ) 
        + dbo.fn_data2cdata(N'node', N'mouth_name',       @mth_id,  @mouth_name )
        + dbo.fn_data2cdata(N'node', N'descript',         null,     @descript )    
        + dbo.fn_data2cdata(N'node', N'link',             null,     @link )
        + dbo.fn_data2cdata(N'node', N'drainage',         null,     @drainage )    
        + dbo.fn_data2cdata(N'node', N'discharge',        null,     @discharge )
        + dbo.fn_data2cdata(N'node', N'watershield',      null,     @watershield ) 
        + dbo.fn_data2cdata(N'node', N'fishing',          null,     @fishing )
        + dbo.fn_data2cdata(N'node',  N'alt_name',        null,     @alt_name )
        + N'<tributary>' + dbo.fn_xml_tributary(@lake_id , 0) + N'</tributary>'
        + N'<fish>' + @fish + N'</fish>'
        + CASE WHEN NULLIF(@vals, '') IS NULL THEN '' ELSE '<node name="MLI">' + @vals + '</node>' END
        + '</root>';
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetTopNews' AND xtype = 'IF')
    DROP function dbo.fn_GetTopNews
GO
/* 
 select * FROM dbo.fn_GetTopNews('4b3c2821-af05-4790-9fb8-37f6ba6abf7c', 'CA')
 */
CREATE FUNCTION [dbo].[fn_GetTopNews]
(
    @newsId  uniqueidentifier,
    @country CHAR(2) = NULL   -- NULL or '' or '  ' → all countries
)
RETURNS TABLE
AS
RETURN
(
    SELECT
          n.news_id, n.news_stamp, n.country, n.news_title,
          n.news_author_link, n.news_author,
          n.news_source_link, n.news_source,
          n.news_photo_author0, n.lake_id,
          n.news_paragraph0, n.news_paragraph1, n.news_photo0,
          0 AS ORD, n.id,
          (SELECT f.fish_name FROM fish f WHERE f.fish_id = n.fish1_id) AS fish1_name,
          (SELECT f.fish_name FROM fish f WHERE f.fish_id = n.fish2_id) AS fish2_name,
          (SELECT f.fish_name FROM fish f WHERE f.fish_id = n.fish3_id) AS fish3_name,
          (SELECT l.lake_name FROM lake l WHERE l.lake_id = n.lake_id) AS lake_name
    FROM dbo.news n
    WHERE n.news_id = @newsId
      AND n.news_title <> 'title'
      AND (
            NULLIF(LTRIM(RTRIM(@country)), '') IS NULL
            OR n.country = @country
          )

    UNION ALL

    SELECT TOP (24)
          n.news_id, n.news_stamp, n.country, n.news_title,
          n.news_author_link, n.news_author,
          n.news_source_link, n.news_source,
          n.news_photo_author0, n.lake_id,
          n.news_paragraph0, n.news_paragraph1,
          CAST(NULL AS varbinary(max)) AS news_photo0,
          1 AS ORD, n.id,
          NULL, NULL, NULL, NULL
    FROM dbo.news n
    WHERE n.news_id <> @newsId
      AND n.news_title <> 'title'
      AND (
            NULLIF(LTRIM(RTRIM(@country)), '') IS NULL
            OR n.country = @country
          )
    ORDER BY n.id DESC
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_view_info' AND xtype = 'TF')
    DROP function dbo.fn_lake_view_info ;
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_laketypebyint' AND xtype = 'FN')
    DROP function dbo.fn_laketypebyint;
GO
--- SELECT dbo.fn_laketypebyint(2)

CREATE function dbo.fn_laketypebyint( @type int )
RETURNS varchar(32)
AS
BEGIN
  RETURN
  CASE WHEN @type = 1 THEN 'Lake'
  WHEN @type = 2     THEN 'River'
  WHEN @type = 4     THEN 'Stream'
  WHEN @type = 8     THEN 'Pond'
  WHEN @type = 64    THEN 'Creek'
  WHEN @type = 128   THEN 'Channel'
  WHEN @type = 8912  THEN 'Reservoir'
  WHEN @type = 16385 THEN 'Sea'
  END
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_view_info' AND xtype = 'TF')
    DROP function dbo.fn_lake_view_info ;
GO

/******
 * get description data related to lake
 * used for lake viewer
 *
 * INPUT PARAMETERS:
 *    @lake uniqueidentifier        -- lake id
 *
 *    Usage:    
                SELECT cast(doc AS xml), img FROM dbo.fn_lake_view_info('890c315e-ba2a-11d8-92e2-080020a0f4c9')
				SELECT cast(doc AS xml), img FROM dbo.fn_lake_view_info('2177FAC1-D376-429F-8AC2-DF4B0E555CA1')
				SELECT cast(doc AS xml), img FROM dbo.fn_lake_view_info('666a39da-ba2a-11d8-92e2-080020a0f4c9')
                SELECT cast(doc AS xml) as doc, img FROM dbo.fn_lake_view_info('22222222-2222-2222-2222-2222222222222')
                SELECT cast(doc AS xml), img FROM dbo.fn_lake_view_info('0CC463B6-849C-20C3-219D-AD76583F5015')
                SELECT * FROM dbo.fn_ViewTributary( 'fc0d917b-d053-11d8-92e2-080020a0f4c9', 0 )
                select * from lake where lake_id = '1EB8EABC-BE3C-11D8-92E2-080020A0F4C9'
                SELECT TOP 1 lake_image_pic FROM dbo.lake_image WHERE lake_image_ownerid = 'fc0d917b-d053-11d8-92e2-080020a0f4c9'

				SELECT * FROM dbo.vw_lake WHERE  lake_id = 'FC0D917B-D053-11D8-92E2-080020A0F4C9'
 */
CREATE function dbo.fn_lake_view_info(@lake_id uniqueidentifier)
  RETURNS @rst TABLE (doc nvarchar(max), img varbinary(max))
AS
BEGIN
    DECLARE @main nvarchar(max), @name sysname, @native nvarchar(255), @french_name nvarchar(255), @lake_road_access nvarchar(255)
        , @source_name nvarchar(255), @mouth_name nvarchar(255), @fish nvarchar(max), @descript nvarchar(max), @link nvarchar(2048)
        , @drainage nvarchar(128), @discharge nvarchar(128), @watershield nvarchar(128), @fishing nvarchar(max), @alt_name nvarchar(64)
        , @src_id uniqueidentifier, @mth_id uniqueidentifier, @science nvarchar(max), @lat float, @lon float
		, @surface int
    ;WITH cte AS
    (
        SELECT l.lake_id, l.lake_name, l.alt_name, l.[native], l.french_name 
        , l.stamp, l.locType, l.link, l.depth, l.width, l.length, l.volume
        , l.isFish, l.noFish, l.isolated, l.is_fishing_prohibited, l.sid, l.drainage, l.discharge, l.watershield, l.basin
        , l.surface, l.shoreline
		, CASE WHEN l.lake_road_access LIKE w.source_district + N'%' THEN NULL ELSE l.lake_road_access END AS lake_road_access
		, l.CGNDB, l.descript, l.fishing
        , w.source_name, w.mouth_name, w.source_state, w.source_country, l.source, l.mouth, w.lat, w.lon
      FROM dbo.lake l JOIN dbo.vw_lake w ON l.lake_id=w.lake_id 
    )
    SELECT @main = val, @name = lake_name, @native = [native], @french_name = french_name, @descript = descript
         , @lake_road_access = lake_road_access, @source_name = source_name, @mouth_name = mouth_name, @link = link
         , @drainage = drainage, @discharge = discharge, @watershield = watershield, @fishing = fishing, @alt_name = alt_name
         , @src_id = source, @mth_id = mouth, @lat = lat, @lon = lon , @surface = surface
         FROM
    (
        SELECT * FROM
        (
            SELECT lake_id, stamp, locType, depth, width, length, volume, surface, shoreline, CGNDB, source_state, source_country
                 , COALESCE(isfish, 0) AS is_fish, COALESCE(noFish, 0) AS no_fish, COALESCE(is_fishing_prohibited, 0) AS is_fishing_prohibited
                 , isolated, link, basin, sid, drainage, discharge, watershield, fishing, source, mouth
				 , dbo.fn_laketypebyint(locType) AS [type], lat, lon
                 FROM cte WHERE lake_id = @lake_id
        ) t FOR XML RAW ('lake')
    ) x(val), cte WHERE lake_id = @lake_id;
	-- fish node 
    SELECT  @fish = COALESCE(val, '') FROM
    ( 
        SELECT * FROM
        (
            SELECT l.fish_id, fish_name, l.link FROM lake_fish l JOIN fish f  ON l.fish_id = f.fish_id WHERE lake_id = @lake_id
        ) t FOR XML RAW ('fish')
    ) x(val)
	-- science data log
    SELECT  @science = COALESCE(val, '') FROM
    ( 
        SELECT * FROM
        (
			 SELECT max(CAST(wd.stamp AS DATE)) AS dt 
				FROM WaterData wd JOIN WaterStation ws ON wd.mli = ws.mli 
				WHERE lakeid = @lake_id
		) t FOR XML RAW ('science')
    ) y(val)
	-- fish spots
	declare @fishspot nvarchar(max);

    SELECT  @fishspot = COALESCE(val, '') FROM
    ( 
        SELECT * FROM
        (
			 SELECT spot_lat, spot_lon 
				FROM Spot a JOIN lake d ON a.lake_id = d.lake_id 
				WHERE d.lake_id = @lake_id
		) t FOR XML RAW ('fishspot')
    ) y(val)

    DECLARE @vals nvarchar(max) = (SELECT STRING_AGG(mli, ',') FROM WaterStation WHERE lakeid=@lake_id);
    IF @vals IS NULL
    BEGIN
        SET @vals = '';
    END
    DECLARE @blob nvarchar(max) = '<?xml version="1.0"?><root>' + @main
        + dbo.fn_data2cdata(N'node', N'lake_name',        null,     @name )        
        + dbo.fn_data2cdata(N'node', N'native',           null,     @native )
        + dbo.fn_data2cdata(N'node', N'french_name',      null,     @french_name ) 
        + dbo.fn_data2cdata(N'node', N'lake_road_access', null,     @lake_road_access )
        + dbo.fn_data2cdata(N'node', N'source_name',      @src_id,  @source_name ) 
        + dbo.fn_data2cdata(N'node', N'mouth_name',       @mth_id,  @mouth_name )
        + dbo.fn_data2cdata(N'node', N'descript',         null,     @descript )    
        + dbo.fn_data2cdata(N'node', N'link',             null,     @link )
        + dbo.fn_data2cdata(N'node', N'drainage',         null,     @drainage )    
        + dbo.fn_data2cdata(N'node', N'discharge',        null,     @discharge )
        + dbo.fn_data2cdata(N'node', N'watershield',      null,     @watershield ) 
        + dbo.fn_data2cdata(N'node', N'fishing',          null,     @fishing )
        + dbo.fn_data2cdata(N'node',  N'alt_name',        null,     @alt_name )
        + CASE WHEN NULLIF(@vals, '') IS NULL THEN '' ELSE '<node name="MLI">' + @vals + '</node>' END
        + N'<tributary>' + dbo.fn_xml_tributary(@lake_id , 0) + N'</tributary>'
        + N'<fish>' + @fish + N'</fish>'
		+ N'<science>' + @science + N'</science>'
		+ N'<fishspot>' + @fishspot + N'</fishspot>'
        + '</root>';
    INSERT INTO @rst 
        SELECT @blob, (SELECT TOP 1 lake_image_pic FROM dbo.lake_image WHERE lake_image_ownerid = @lake_id) AS lake_image_pic
    RETURN
END
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_forecast_plot_json' AND xtype = 'FN')
    DROP function dbo.fn_forecast_plot_json ;
GO


-- provide values for FishTracker.Forecast.Plot.GetJsonPlot
-- select dbo.fn_forecast_plot_json (142266, '4db64c3d-95cc-4e19-85be-c2a46582f813' )
-- select dbo.fn_forecast_plot_json (266745, '4f023204-cdaf-4fae-bf7f-e9319794e8ff' )
CREATE FUNCTION dbo.fn_forecast_plot_json( @sid int, @fish_guid varchar(255) )
RETURNS nvarchar(MAX)
AS
BEGIN
  DECLARE @rst TABLE (dt date, tm float , lvl float , prc float , dis float , tu float);
  DECLARE @TemperatureList varchar(255) = '';
  DECLARE @WaterLevelList  varchar(255) = '';
  DECLARE @DischargeList  varchar(255) = '';
  DECLARE @Precipitation  varchar(255) = '';
  DECLARE @Turbidity  varchar(255) = '';
  DECLARE @DatesList  varchar(255) = '';
  DECLARE @country char(2) = '';
  DECLARE @state nvarchar(255) = '';
  DECLARE @lakeid uniqueidentifier;
  DECLARE @start date = DATEADD( DAY, -15, GETDATE());
  DECLARE @end date = DATEADD( DAY,  7, GETDATE());
  DECLARE @mli varchar(64), @WaterStation uniqueidentifier 
  SELECT TOP 1 @mli = MLI, @WaterStation = id, @country = country, @lakeid = lakeid,@state = [state]
	FROM WaterStation WITH (NOLOCK) WHERE sid = @sid;
  INSERT INTO @rst (dt) SELECT * from dbo.GetDatePeriod( @start, @end );
  DECLARE @fishName sysname = (SELECT fish_name FROM fish WHERE fish_id = @fish_guid);
  DECLARE @WaterStateDate varchar(32) = (SELECT TOP 1 CAST(stamp AS varchar(32)) FROM [WaterData] where mli = @mli ORDER BY stamp DESC);
  -- convert C to F if US
  UPDATE @rst SET tm = CASE WHEN 'US' = @country THEN ( tm * 2 ) + 30 ELSE tm END FROM @rst;

  UPDATE t SET t.tm  = ( CASE WHEN f.dt = CAST(getutcdate() AS DATE) THEN f.air_temperature ELSE f.tmDay END )
    , t.prc = (COALESCE(f.[gpfDay], 0) + COALESCE(f.[gpfNight], 0))/2.0
    FROM @rst t JOIN weather_Forecast f WITH (NOLOCK) ON (CAST(f.dt AS DATE) = t.dt) 
    WHERE f.mli = @mli;
  UPDATE t SET t.lvl = elevation, t.dis = discharge, t.tu = turbidity 
    FROM @rst t JOIN WaterData f WITH (NOLOCK) 
	ON CAST(CAST(f.stamp AS DATE) AS varchar(10)) = CAST(CAST(t.dt AS DATE) AS varchar(10))
    WHERE f.mli = @mli and ( elevation is not null OR discharge is not null);

 -- UPDATE @rst SET lvl = COALESCE(lvl, 99999), prc = COALESCE(prc, 99999), dis = COALESCE(dis, 99999), tu = COALESCE(tu, 99999), tm = COALESCE(tm, 99999)

  SELECT @DatesList =  @DatesList + '","' + LEFT(DATENAME(dw, dt), 3) + ' ' + CAST(DATEPART(DAY, dt) AS varchar(255) ) + '' FROM @rst ORDER BY dt ASC
  SET @DatesList = RIGHT(@DatesList, LEN(@DatesList)-2) + '"'
  
  SELECT @WaterLevelList =  @WaterLevelList + ',' + dbo.fn_get_float_as_string(lvl) + '' FROM @rst ORDER BY dt ASC
  SET @WaterLevelList = RIGHT(@WaterLevelList, LEN(@WaterLevelList)-1)
  
  SELECT @DischargeList =  @DischargeList + ',' + dbo.fn_get_float_as_string(dis) + '' FROM @rst   ORDER BY dt ASC
  SET @DischargeList = RIGHT(@DischargeList, LEN(@DischargeList)-1)
  
  SELECT @Precipitation =  @Precipitation + ',' + dbo.fn_get_float_as_string(prc) + '' FROM @rst ORDER BY dt ASC
  SET @Precipitation = RIGHT(@Precipitation, LEN(@Precipitation)-1)
  
  SELECT @TemperatureList =  @TemperatureList + ',' + dbo.fn_get_float_as_string(tm) + '' FROM @rst ORDER BY dt ASC
  SET @TemperatureList = RIGHT(@TemperatureList, LEN(@TemperatureList)-1)

  SELECT @Turbidity =  @Turbidity + ',' + dbo.fn_get_float_as_string(tu) + '' FROM @rst ORDER BY dt ASC
  SET @Turbidity = RIGHT(@Turbidity, LEN(@Turbidity)-1)

  DECLARE @placeDesc varchar(max) = (SELECT TOP 1 REPLACE(locDesc, '"', '''') FROM WaterStation WITH (NOLOCK) WHERE id = @waterStation);
  IF @placeDesc IS NULL SET @placeDesc = 'unknown'

  DECLARE @result nvarchar(MAX) = N'"place":"' + @placeDesc  + '"'
	+ ', "fish":"' + COALESCE(@fishName, '') + '"'
	+ ', "country":"' + @country + '"'
	+ ', "state":"' + @state + '"'
	+ ', "stamp":"' + @WaterStateDate + '"'
	+ ', "lakeid":"' + CAST(@lakeid as varchar(36)) + '"'
	+ ', "date":['          + @DatesList        + ']'
	+ ', "discharge":['     + @DischargeList   + ']'
	+ ', "precipitation":[' + @Precipitation   + ']'
	+ ', "temperature":['   + @TemperatureList + ']'
	+ ', "turbidity":['     + @Turbidity       + ']'
	+ ', "level":['         + @WaterLevelList  + ']';

  RETURN '{' + @result + '}';
end;
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
 IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_plot_weather' AND xtype = 'IF')
    DROP function dbo.fn_plot_weather ;
GO

/******
-- Called from FishTracker.Forecast.Plot.LoadPlaceLatLon
-- for 23 row set of data in the range from -15 to +10 days 
-- SELECT * FROM dbo.vw_plot_weather WHERE sid=263810
 *
 * INPUT PARAMETERS:
 *    @sid int        -- station id
 *
 *    Usage:    
         SELECT * FROM dbo.fn_plot_weather(226689)
		-- select top 1 ows  from ows_meteo where ows is not null order by stamp desc
 */
CREATE function dbo.fn_plot_weather(@sid int)
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    WITH cte AS 
	(
		SELECT CAST( dt AS DATE) AS dt  FROM dbo.weather_Forecast wf 
        JOIN dbo.WaterStation wt on wt.mli = wf.mli
        WHERE dt >= CAST(DATEADD(DAY, -15, getdate()) AS DATE) AND wt.sid = @sid
	) 
	SELECT  TOP 50 dt,  wind_degree, precipitation, humidity, wind_direction, pressure, temperature_low, temperature_high, wind_max_speed
	      , shortText, longText, icon, sid FROM
    (
    SELECT dt,  wind_degree
    , CAST(ISNULL(rain_today, 0.0) AS INT) AS precipitation
    , humidity, wind_direction
    , ISNULL(ROUND(pressure, 1), 0.0) AS pressure
    , CAST(ROUND(tmLow, 1)  AS INT)   AS temperature_low
    , CAST(ROUND(tmHigh, 1) AS INT)   AS temperature_high
    , CAST(ROUND(wind_max_speed, 1)   AS INT) AS wind_max_speed
    , shortText, longText, icon, wt.sid as sid
      FROM dbo.weather_Forecast wf 
        JOIN dbo.WaterStation wt on wt.mli = wf.mli
        WHERE dt >= CAST(DATEADD(DAY, -15, getdate()) AS DATE) AND wt.sid = @sid
	UNION ALL
	SELECT CAST(q.dt AS DATE) as dt, 0 wind_degree, 0 AS precipitation, 0 humidity, '' wind_direction
	, 0.0 pressure, 0 temperature_low, 0 temperature_high, 0 wind_max_speed, '' shortText, '' longText, null icon, @sid as sid FROM 
		(
		    SELECT CAST(DATEADD(DAY, dt-15, getdate()) AS DATE) as dt FROM (VALUES  (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15), (16), (17), (18), (19), (20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30))  AS x(dt)
		)q
		WHERE q.dt NOT IN (SELECT dt FROM cte )
	)z
	ORDER BY dt ASC
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_state' AND xtype = 'IF')
    DROP function dbo.fn_lake_state;
GO
/*
--- SELECT * FROM dbo.fn_lake_state('0C21DC6B-849C-20C3-CAF9-000CDAA217E3', 3)
--   select * from Lake_State where lake_id = '743a5733-bf0d-11d8-92e2-080020a0f4c9'
*/
CREATE function dbo.fn_lake_state( @lake_id uniqueidentifier,  @month int )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
	SELECT TOP 1 lake_id, lake_name, pH, phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium, Chloride
		, Bicarbonate, transparency, oxygen, Salinity, clarity, velocity, water_degree, air_degree, cold_cool, flow_stand
		, Stamp FROM
	(
		SELECT l.lake_id, lake_name, s.Stamp
			 , s.pH, s.phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium, Chloride, Bicarbonate
			 , transparency, oxygen, Salinity, clarity, s.velocity, water_degree, air_degree, cold_cool, flow_stand, [month]
			   FROM dbo.Lake_State s JOIN dbo.lake l ON l.lake_id = s.lake_id
			   WHERE l.lake_id = @lake_id AND s.[month] = @month
		UNION ALL  
		SELECT TOP 1 l.lake_id, lake_name, s.Stamp
			 , s.pH, s.phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium, Chloride, Bicarbonate
			 , transparency, oxygen, Salinity, clarity, s.velocity, water_degree, air_degree, cold_cool, flow_stand, [month]
			   FROM dbo.Lake_State s JOIN dbo.lake l ON l.lake_id = s.lake_id
			   WHERE l.lake_id = @lake_id ORDER BY stamp DESC
    )x
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_view_news' AND xtype = 'IF')
    DROP function dbo.fn_river_view_news;
GO
-- select * FROM dbo.fn_river_view_news('c586fb25-ba2a-11d8-92e2-080020a0f4c9',1)
-- select * FROM dbo.fn_river_view_news('cccca0b9-fb01-4865-b4ec-3409da3e7fd4',1) -- Lake Shasta
-- Used in RiverViewer.aspx

CREATE function dbo.fn_river_view_news( @lake_id uniqueidentifier, @col int )
RETURNS  TABLE
  WITH SCHEMABINDING
AS
  RETURN
    SELECT news_id, news_title, news_stamp, news_source FROM
	(
		SELECT top 12 row_number() over (order by news_stamp desc) as num, news_id, news_title
			   , CONVERT(varchar(10), news_stamp, 103) AS news_stamp, news_source 
		FROM dbo.news WHERE @lake_id = lake_id
	)x
	WHERE @col = num % 2
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
/*
    Calculates the current UTC-day page count from dbo.SessionHandler for the specified client IP address (IPv4 and/or IPv6) and host, 
    excluding rows marked as banned, and returns the aggregated counterPage value as an integer.
*/
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_SessionHandlerTodayConsumedPages' AND xtype = 'FN')
    DROP function dbo.fn_SessionHandlerTodayConsumedPages;
GO

CREATE FUNCTION dbo.fn_SessionHandlerTodayConsumedPages (@ip4 VARCHAR(45), @host VARCHAR(255) )
    RETURNS INT
    WITH SCHEMABINDING
    AS
    BEGIN
        DECLARE @result INT;

        SELECT @result = ISNULL(SUM(ISNULL(counterPage, 0)), 0)
        FROM dbo.SessionHandler
        WHERE CAST(startSess AS date) = CAST(GETUTCDATE() AS date)
          AND host = @host
          AND ISNULL(baned, 0) = 0
          AND (@ip4 <> '''' AND ip4 = @ip4);

        RETURN ISNULL(@result, 0);
    END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'IsIpBanned' AND xtype = 'FN')
    DROP function dbo.IsIpBanned
GO
/*
    SELECT TOP 1 id FROM SessionHandler WHERE baned = 1 AND (ip4 = '99.250.66.125')

    Used in Global.aspx.cs
*/
CREATE FUNCTION dbo.IsIpBanned( @ip4 VARCHAR(45) )
RETURNS BIT
AS
BEGIN
    DECLARE @result BIT = 0;

    IF (@ip4 IS NULL OR @ip4 = '')
        RETURN 0;

    IF EXISTS (
        SELECT 1 FROM dbo.SessionHandler WHERE baned = 1 AND ip4 = @ip4
    )
        SET @result = 1;

    RETURN @result;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_Ipv4ToBigint' AND xtype = 'FN')
    DROP function dbo.fn_Ipv4ToBigint
GO
/*
    Converts a dotted-quad IPv4 string ('a.b.c.d') to its 32-bit numeric value as a BIGINT
    (a*2^24 + b*2^16 + c*2^8 + d). Returns NULL for anything that is not a valid IPv4 address
    (NULL/empty, IPv6, wrong octet count, non-numeric or out-of-range octets). Used to range-match
    a caller IP against dbo.CloudProviderIpRange. PARSENAME splits on '.' and yields NULL unless
    there are exactly four parts, which also rejects 5+ part strings.
*/
CREATE FUNCTION dbo.fn_Ipv4ToBigint( @ip4 VARCHAR(45) )
RETURNS BIGINT
AS
BEGIN
    IF (@ip4 IS NULL OR @ip4 = '')
        RETURN NULL;

    DECLARE @o1 INT = TRY_CONVERT(INT, PARSENAME(@ip4, 4));
    DECLARE @o2 INT = TRY_CONVERT(INT, PARSENAME(@ip4, 3));
    DECLARE @o3 INT = TRY_CONVERT(INT, PARSENAME(@ip4, 2));
    DECLARE @o4 INT = TRY_CONVERT(INT, PARSENAME(@ip4, 1));

    IF (@o1 IS NULL OR @o2 IS NULL OR @o3 IS NULL OR @o4 IS NULL)
        RETURN NULL;
    IF (@o1 NOT BETWEEN 0 AND 255 OR @o2 NOT BETWEEN 0 AND 255
        OR @o3 NOT BETWEEN 0 AND 255 OR @o4 NOT BETWEEN 0 AND 255)
        RETURN NULL;

    RETURN CAST(@o1 AS BIGINT) * 16777216 + @o2 * 65536 + @o3 * 256 + @o4;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'IsCloudProviderIp' AND xtype = 'FN')
    DROP function dbo.IsCloudProviderIp
GO
/*
    Returns 1 when @ip4 falls inside any datacenter / cloud-provider range in dbo.CloudProviderIpRange
    (AWS, GCP, Azure, Oracle, DigitalOcean, Alibaba, ...), otherwise 0. Because the stored ranges are
    disjoint, the single range that could contain @n is the one with the greatest ipStart <= @n; one
    index seek (IX_CPIR_ipStart) finds it and we confirm @n <= ipEnd. NULL/invalid IPs return 0.

    Used by Global.asax.cs (via dbo.IsIpBlocked) to refuse requests from hosting networks.
*/
CREATE FUNCTION dbo.IsCloudProviderIp( @ip4 VARCHAR(45) )
RETURNS BIT
AS
BEGIN
    DECLARE @n BIGINT = dbo.fn_Ipv4ToBigint(@ip4);

    IF (@n IS NULL)
        RETURN 0;

    DECLARE @ipEnd BIGINT;

    -- disabled = 0 only: a manually disabled range is excluded from blocking. Ranges are disjoint,
    -- so if the one range that could contain @n is disabled, no other (lower) enabled range covers it.
    SELECT TOP 1 @ipEnd = ipEnd
    FROM dbo.CloudProviderIpRange
    WHERE ipStart <= @n
      AND disabled = 0
    ORDER BY ipStart DESC;

    IF (@ipEnd IS NOT NULL AND @ipEnd >= @n)
        RETURN 1;

    RETURN 0;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'IsIpBlocked' AND xtype = 'FN')
    DROP function dbo.IsIpBlocked
GO
/*
    Single entry point used by Global.asax.cs BeginRequest to decide whether to refuse a request:
    returns 1 if the IP is explicitly banned in SessionHandler (manual / rate-limit ban) OR it belongs
    to a known cloud / datacenter provider range. Keeping both checks behind one scalar means one DB
    round-trip per request. NULL/invalid/empty IPs return 0.
*/
CREATE FUNCTION dbo.IsIpBlocked( @ip4 VARCHAR(45) )
RETURNS BIT
AS
BEGIN
    IF (dbo.IsIpBanned(@ip4) = 1)
        RETURN 1;
    IF (dbo.IsCloudProviderIp(@ip4) = 1)
        RETURN 1;

    RETURN 0;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_list' AND xtype = 'IF')
    DROP function dbo.fn_catch_memo_list
GO
--    @viewer_id NULL  => guest (coordinates are returned as NULL).
--    Private memos are returned only to their author and to admins.
--    can_edit reflects author + 60-day lock (admins always 1).
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_list
(
    @lake_id   UNIQUEIDENTIFIER,
    @viewer_id UNIQUEIDENTIFIER,
    @is_admin  BIT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        m.catch_memo_id,
        m.catch_memo_lake_id,
        m.catch_memo_userid,
        m.catch_memo_fish_id,
        COALESCE(NULLIF(m.catch_memo_species, N''), f.fish_name) AS catch_memo_species,
        f.fish_latin AS catch_memo_fish_latin,
        m.catch_memo_title,
        m.catch_memo_text,
        CASE WHEN @viewer_id IS NULL THEN NULL ELSE m.catch_memo_lat END AS catch_memo_lat,
        CASE WHEN @viewer_id IS NULL THEN NULL ELSE m.catch_memo_lon END AS catch_memo_lon,
        m.catch_memo_method,
        m.catch_memo_tackle,
        m.catch_memo_lure,
        m.catch_memo_catch_date,
        m.catch_memo_weight,
        m.catch_memo_weight_unit,
        m.catch_memo_length,
        m.catch_memo_length_unit,
        m.catch_memo_released,
        m.catch_memo_private,
        m.catch_memo_weather_temp,
        m.catch_memo_weather_pressure,
        m.catch_memo_weather_text,
        m.catch_memo_weather_icon,
        m.catch_memo_water_temp,
        m.catch_memo_created,
        m.catch_memo_updated,
        u.userName AS catch_memo_user_name,
        (SELECT COUNT(*)        FROM dbo.catch_memo_photo p WHERE p.catch_memo_photo_memoid = m.catch_memo_id) AS photo_count,
        CAST(CASE
            WHEN @is_admin = 1 THEN 1
            WHEN @viewer_id IS NOT NULL AND m.catch_memo_userid = @viewer_id
                 AND DATEDIFF(DAY, m.catch_memo_created, SYSUTCDATETIME()) <= 60 THEN 1
            ELSE 0
        END AS BIT) AS can_edit,
        -- Personal best: this catch's weight (normalized to kg) equals the author's max for this
        -- species (by fish_id) across all their catches. Ties are all flagged; free-text species
        -- (no fish_id) and weightless catches never qualify.
        CAST(CASE
            WHEN m.catch_memo_fish_id IS NOT NULL AND m.catch_memo_weight IS NOT NULL
                 AND pb.best_weight_kg IS NOT NULL
                 AND ( CASE WHEN m.catch_memo_weight_unit = 'lb' THEN m.catch_memo_weight * 0.45359237 ELSE m.catch_memo_weight END )
                     = pb.best_weight_kg
            THEN 1 ELSE 0
        END AS BIT) AS catch_memo_is_pb,
        COALESCE(lf.status, 0) AS catch_memo_fish_status
    FROM dbo.catch_memo m
    LEFT JOIN dbo.fish  f ON f.fish_id = m.catch_memo_fish_id
    LEFT JOIN dbo.Users u ON u.id      = m.catch_memo_userid
    LEFT JOIN dbo.lake_fish lf ON lf.lake_Id = m.catch_memo_lake_id AND lf.fish_Id = m.catch_memo_fish_id
    OUTER APPLY (
        SELECT MAX(CASE WHEN m2.catch_memo_weight_unit = 'lb' THEN m2.catch_memo_weight * 0.45359237 ELSE m2.catch_memo_weight END) AS best_weight_kg
        FROM dbo.catch_memo m2
        WHERE m2.catch_memo_userid  = m.catch_memo_userid
          AND m2.catch_memo_fish_id = m.catch_memo_fish_id
          AND m2.catch_memo_weight IS NOT NULL
    ) pb
    WHERE m.catch_memo_lake_id = @lake_id
      AND ( @is_admin = 1
            OR ( @viewer_id IS NOT NULL AND m.catch_memo_userid = @viewer_id )
            -- Everyone else (guests + other logged-in users) sees a memo only when it is
            -- public AND "complete". An incomplete draft -- no catch date AND no visible
            -- (non-hidden) photo -- stays visible to its author and admins only, so a bare
            -- stub that a registered user started but never filled in never shows publicly.
            OR ( m.catch_memo_private = 0
                 AND ( m.catch_memo_catch_date IS NOT NULL
                       OR EXISTS ( SELECT 1 FROM dbo.catch_memo_photo p
                                   WHERE p.catch_memo_photo_memoid = m.catch_memo_id
                                     AND p.catch_memo_photo_hidden  = 0 ) ) ) )
);
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
-- fn_catch_memo_json : complete JSON export of a single catch memo, for the admin-only
-- "Download JSON" link on the Fishing page. Includes every memo column, the resolved fish
-- name/latin, the author's display name, the selected photos (metadata + the image bytes as
-- base64 -- FOR JSON base64-encodes varbinary automatically) and ALL comments. Returns a single
-- JSON object, or NULL when the memo id does not exist. No visibility filtering here: the caller
-- (the web page / endpoint) is responsible for restricting this to admins.
--
-- @top_photos controls how many photos are embedded (they dominate the payload size):
--     NULL (default) -> ALL photos, including hidden ones (full export).
--     0              -> NO photos (metadata/comments only).
--     1              -> the single best photo: most-liked, ties broken by first-added
--                       (ord, then upload time); if none are liked this is just the first-added.
--     n (> 1)        -> the top n photos by that same "best" ranking, if that many exist.
-- For any positive @top_photos only NON-hidden photos are eligible (matching the public gallery);
-- NULL still returns everything so an admin can audit hidden/removed photos.
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_json (@memo_id UNIQUEIDENTIFIER, @top_photos INT = NULL)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN
    (
        SELECT
            m.catch_memo_id,
            m.catch_memo_lake_id,
            m.catch_memo_userid,
            u.userName   AS catch_memo_user_name,
            m.catch_memo_fish_id,
            f.fish_name  AS catch_memo_fish_name,
            f.fish_latin AS catch_memo_fish_latin,
            m.catch_memo_species,
            m.catch_memo_title,
            m.catch_memo_text,
            m.catch_memo_lat,
            m.catch_memo_lon,
            m.catch_memo_method,
            m.catch_memo_tackle,
            m.catch_memo_lure,
            m.catch_memo_catch_date,
            m.catch_memo_weight,
            m.catch_memo_weight_unit,
            m.catch_memo_length,
            m.catch_memo_length_unit,
            m.catch_memo_released,
            m.catch_memo_private,
            m.catch_memo_weather_temp,
            m.catch_memo_weather_pressure,
            m.catch_memo_weather_text,
            m.catch_memo_weather_icon,
            m.catch_memo_water_temp,
            m.catch_memo_created,
            m.catch_memo_updated,
            m.catch_memo_cloned_from,
            (
                SELECT
                    p.catch_memo_photo_id,
                    p.catch_memo_photo_label,
                    p.catch_memo_photo_description,
                    p.catch_memo_photo_author,
                    p.catch_memo_photo_ord,
                    p.catch_memo_photo_stamp,
                    p.catch_memo_photo_hidden,
                    DATALENGTH(p.catch_memo_photo_pic) AS catch_memo_photo_bytes,
                    p.catch_memo_photo_pic
                FROM dbo.catch_memo_photo p
                WHERE p.catch_memo_photo_memoid = m.catch_memo_id
                  AND (
                        @top_photos IS NULL                 -- all photos (incl. hidden)
                        OR (
                            @top_photos > 0                 -- top-n by "best" ranking, visible only
                            AND p.catch_memo_photo_hidden = 0
                            AND p.catch_memo_photo_id IN (
                                SELECT TOP (COALESCE(@top_photos, 0)) p2.catch_memo_photo_id
                                FROM dbo.catch_memo_photo p2
                                WHERE p2.catch_memo_photo_memoid = m.catch_memo_id
                                  AND p2.catch_memo_photo_hidden = 0
                                ORDER BY ( SELECT COUNT(*) FROM dbo.catch_memo_photo_like l
                                           WHERE l.catch_memo_photo_like_photoid = p2.catch_memo_photo_id ) DESC,
                                         p2.catch_memo_photo_ord  ASC,
                                         p2.catch_memo_photo_stamp ASC
                            )
                        )
                      )                                     -- @top_photos = 0 (or negative) -> no rows
                ORDER BY p.catch_memo_photo_ord, p.catch_memo_photo_stamp
                FOR JSON PATH, INCLUDE_NULL_VALUES
            ) AS photos,
            (
                SELECT
                    c.catch_memo_comment_id,
                    c.catch_memo_comment_userid,
                    cu.userName AS catch_memo_comment_user_name,
                    c.catch_memo_comment_text,
                    c.catch_memo_comment_created,
                    c.catch_memo_comment_deleted
                FROM dbo.catch_memo_comment c
                LEFT JOIN dbo.Users cu ON cu.id = c.catch_memo_comment_userid
                WHERE c.catch_memo_comment_memoid = m.catch_memo_id
                ORDER BY c.catch_memo_comment_created
                FOR JSON PATH, INCLUDE_NULL_VALUES
            ) AS comments
        FROM dbo.catch_memo m
        LEFT JOIN dbo.fish  f ON f.fish_id = m.catch_memo_fish_id
        LEFT JOIN dbo.Users u ON u.id      = m.catch_memo_userid
        WHERE m.catch_memo_id = @memo_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
END
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_get' AND xtype = 'IF')
    DROP function dbo.fn_catch_memo_get
GO
-- 5. fn_catch_memo_get : single memo for the edit form -----------------------
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_get
(
    @memo_id   UNIQUEIDENTIFIER,
    @viewer_id UNIQUEIDENTIFIER,
    @is_admin  BIT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        m.catch_memo_id,
        m.catch_memo_lake_id,
        m.catch_memo_userid,
        m.catch_memo_fish_id,
        m.catch_memo_species,
        m.catch_memo_title,
        m.catch_memo_text,
        m.catch_memo_lat,
        m.catch_memo_lon,
        m.catch_memo_method,
        m.catch_memo_tackle,
        m.catch_memo_lure,
        m.catch_memo_catch_date,
        m.catch_memo_weight,
        m.catch_memo_weight_unit,
        m.catch_memo_length,
        m.catch_memo_length_unit,
        m.catch_memo_released,
        m.catch_memo_private,
        m.catch_memo_weather_temp,
        m.catch_memo_weather_pressure,
        m.catch_memo_weather_text,
        m.catch_memo_weather_icon,
        m.catch_memo_water_temp,
        m.catch_memo_created,
        m.catch_memo_updated,
        CAST(CASE
            WHEN @is_admin = 1 THEN 1
            WHEN @viewer_id IS NOT NULL AND m.catch_memo_userid = @viewer_id
                 AND DATEDIFF(DAY, m.catch_memo_created, SYSUTCDATETIME()) <= 60 THEN 1
            ELSE 0
        END AS BIT) AS can_edit
    FROM dbo.catch_memo m
    WHERE m.catch_memo_id = @memo_id
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_pending_clone_id' AND xtype = 'FN')
    DROP FUNCTION dbo.fn_catch_memo_pending_clone_id
GO
-- fn_catch_memo_pending_clone_id : the id of this user's unfinished clone, if any. A clone (see
-- sp_clone_catch_memo -- catch_memo_cloned_from IS NOT NULL) is "unfinished" until it has a
-- species (catalog fish_id or free-text species) AND at least one non-hidden photo -- until then,
-- the user may not start cloning another memo (wfCatchMemoEdit.aspx.cs enforces this both when
-- rendering the "Clone" link and again here before creating a new clone).
CREATE FUNCTION dbo.fn_catch_memo_pending_clone_id(@userid UNIQUEIDENTIFIER)
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    DECLARE @id UNIQUEIDENTIFIER;
    SELECT TOP 1 @id = m.catch_memo_id
    FROM dbo.catch_memo m
    WHERE m.catch_memo_userid = @userid
      AND m.catch_memo_cloned_from IS NOT NULL
      AND (
            (m.catch_memo_fish_id IS NULL AND (m.catch_memo_species IS NULL OR LTRIM(RTRIM(m.catch_memo_species)) = N''))
         OR NOT EXISTS (SELECT 1 FROM dbo.catch_memo_photo p
                         WHERE p.catch_memo_photo_memoid = m.catch_memo_id AND p.catch_memo_photo_hidden = 0)
          );
    RETURN @id;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_weather_snapshot' AND xtype = 'IF')
    DROP function dbo.fn_catch_weather_snapshot
GO
-- fn_catch_weather_snapshot : weather to stamp onto a catch_memo at save time. Picks the water
-- body's station (dbo.WaterStation.lakeId) and its dbo.weather_Forecast row for that calendar
-- date (air temp/pressure/conditions -- retained ~15 days back / 10 days forward; naturally
-- comes back NULL once @catch_date falls outside that window, since no forecast row exists).
-- dbo.CurrentWaterState is different: it holds a single "right now" reading per station with NO
-- date dimension at all (PK is just mli), so it is only joined when @catch_date is today or
-- yesterday -- otherwise a backdated catch would silently get today's water temp misattributed
-- to it. Returns zero rows only when the lake has no station at all -- caller treats a missing
-- row as "no snapshot".
CREATE OR ALTER FUNCTION dbo.fn_catch_weather_snapshot
(
    @lake_id    UNIQUEIDENTIFIER,
    @catch_date DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 1
        wf.tmHigh       AS weather_temp,
        wf.pressure     AS weather_pressure,
        wf.shortText    AS weather_text,
        wf.icon         AS weather_icon,
        cws.temperature AS water_temp
    FROM dbo.WaterStation ws
    LEFT JOIN dbo.weather_Forecast  wf  ON wf.mli  = ws.mli AND wf.dt = @catch_date
    LEFT JOIN dbo.CurrentWaterState cws ON cws.mli = ws.mli
                                        AND @catch_date >= CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)
    WHERE ws.lakeId = @lake_id
    ORDER BY wf.tm
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------

-- 6. fn_catch_memo_photo_handler : raw bytes for HandlerImage.ashx -----------
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_photo_handler
(
    @memo_id  UNIQUEIDENTIFIER,
    @photo_id UNIQUEIDENTIFIER
)
RETURNS VARBINARY(MAX)
AS
BEGIN
    DECLARE @pic VARBINARY(MAX);
    SELECT TOP 1 @pic = catch_memo_photo_pic
    FROM dbo.catch_memo_photo
    WHERE catch_memo_photo_memoid = @memo_id
      AND catch_memo_photo_id     = @photo_id
      AND catch_memo_photo_hidden = 0;
    RETURN @pic;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_photo_list' AND xtype = 'IF')
    DROP function dbo.fn_catch_memo_photo_list
GO
-- fn_catch_memo_photo_list : photo ids for one memo (gallery). Hidden photos (soft-deleted by a
-- non-admin via sp_del_catch_memo_photo) are excluded -- only a physical delete (admin) removes
-- a row outright.
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_photo_list (@memo_id UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT catch_memo_photo_id, catch_memo_photo_label, catch_memo_photo_ord,
           catch_memo_photo_description, catch_memo_photo_author, catch_memo_photo_stamp
    FROM dbo.catch_memo_photo
    WHERE catch_memo_photo_memoid = @memo_id
      AND catch_memo_photo_hidden = 0
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_photo_gallery' AND xtype = 'IF')
    DROP function dbo.fn_catch_memo_photo_gallery
GO
-- fn_catch_memo_photo_gallery : the gallery for one memo, with per-photo "like" data. This is the
-- like-aware successor to fn_catch_memo_photo_list (kept for backward compat during rollout):
--   * like_count   -- total likes on the photo.
--   * viewer_liked -- 1 when @viewer_id (the logged-in user) has liked it; always 0 for guests.
--   * GUEST RULE: a guest (@viewer_id IS NULL) receives only the single "best" photo -- the
--     most-liked one (ties broken by ord, then upload time). A logged-in user gets every
--     non-hidden photo. (Only logged-in users may like; guests just see the best shot + its count.)
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_photo_gallery
(
    @memo_id   UNIQUEIDENTIFIER,
    @viewer_id UNIQUEIDENTIFIER
)
RETURNS TABLE
AS
RETURN
(
    WITH base AS (
        SELECT
            p.catch_memo_photo_id,
            p.catch_memo_photo_label,
            p.catch_memo_photo_ord,
            p.catch_memo_photo_description,
            p.catch_memo_photo_author,
            p.catch_memo_photo_stamp,
            ( SELECT COUNT(*) FROM dbo.catch_memo_photo_like l
              WHERE l.catch_memo_photo_like_photoid = p.catch_memo_photo_id ) AS like_count,
            CAST(CASE WHEN @viewer_id IS NOT NULL AND EXISTS (
                        SELECT 1 FROM dbo.catch_memo_photo_like l2
                        WHERE l2.catch_memo_photo_like_photoid = p.catch_memo_photo_id
                          AND l2.catch_memo_photo_like_userid  = @viewer_id )
                      THEN 1 ELSE 0 END AS BIT) AS viewer_liked,
            ROW_NUMBER() OVER (
                ORDER BY ( SELECT COUNT(*) FROM dbo.catch_memo_photo_like l3
                           WHERE l3.catch_memo_photo_like_photoid = p.catch_memo_photo_id ) DESC,
                         p.catch_memo_photo_ord ASC,
                         p.catch_memo_photo_stamp ASC ) AS rn
        FROM dbo.catch_memo_photo p
        WHERE p.catch_memo_photo_memoid = @memo_id
          AND p.catch_memo_photo_hidden = 0
    )
    SELECT catch_memo_photo_id, catch_memo_photo_label, catch_memo_photo_ord,
           catch_memo_photo_description, catch_memo_photo_author, catch_memo_photo_stamp,
           like_count, viewer_liked
    FROM base
    WHERE @viewer_id IS NOT NULL   -- logged-in: all non-hidden photos
       OR rn = 1                   -- guest: only the single best photo
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_memo_comment_list' AND xtype = 'IF')
    DROP function dbo.fn_catch_memo_comment_list
GO
-- fn_catch_memo_comment_list : the discussion thread for one memo (oldest-first is applied by the
-- caller's ORDER BY). Returns each comment with its author's display name. Visible to everyone,
-- including guests -- posting is gated, reading is not.
CREATE OR ALTER FUNCTION dbo.fn_catch_memo_comment_list (@memo_id UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT
        c.catch_memo_comment_id,
        c.catch_memo_comment_memoid,
        c.catch_memo_comment_userid,
        c.catch_memo_comment_text,
        c.catch_memo_comment_created,
        c.catch_memo_comment_deleted,
        u.userName AS catch_memo_comment_user_name
    FROM dbo.catch_memo_comment c
    LEFT JOIN dbo.Users u ON u.id = c.catch_memo_comment_userid
    WHERE c.catch_memo_comment_memoid = @memo_id
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_user_message_inbox' AND xtype = 'IF')
    DROP function dbo.fn_user_message_inbox
GO
-- fn_user_message_inbox : the messages RECEIVED by @userid, with the sender's display name and
-- whether @userid has already blocked that sender (so the UI can show Block vs Unblock). The caller
-- orders newest-first.
CREATE OR ALTER FUNCTION dbo.fn_user_message_inbox (@userid UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT
        m.user_message_id,
        m.user_message_from,
        m.user_message_to,
        m.user_message_text,
        m.user_message_created,
        m.user_message_read,
        u.userName AS user_message_from_name,
        CAST(CASE WHEN b.user_message_block_blockedid IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS sender_blocked
    FROM dbo.user_message m
    LEFT JOIN dbo.Users u ON u.id = m.user_message_from
    LEFT JOIN dbo.user_message_block b
           ON b.user_message_block_userid = @userid
          AND b.user_message_block_blockedid = m.user_message_from
    WHERE m.user_message_to = @userid
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
-- fn_user_message_unread_count : how many unread messages @userid has (for a badge / heading).
CREATE OR ALTER FUNCTION dbo.fn_user_message_unread_count (@userid UNIQUEIDENTIFIER)
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM dbo.user_message
            WHERE user_message_to = @userid AND user_message_read = 0);
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
-- fn_user_is_send_banned : 1 when @userid holds an account-level send ban (the >50 anti-spam ban).
CREATE OR ALTER FUNCTION dbo.fn_user_is_send_banned (@userid UNIQUEIDENTIFIER)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM dbo.user_send_ban WHERE user_send_ban_userid = @userid)
                THEN 1 ELSE 0 END;
END
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_fish_list' AND xtype = 'IF')
    DROP function dbo.fn_lake_fish_list
GO
-- fn_lake_fish_list : the species assigned to a water body (catch-memo dropdown)
CREATE OR ALTER FUNCTION dbo.fn_lake_fish_list (@lake_id UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT f.fish_id, f.fish_name
    FROM dbo.lake_fish lf
    JOIN dbo.fish f ON f.fish_id = lf.fish_id
    WHERE lf.lake_Id = @lake_id
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_catch_pending_fish_list' AND xtype = 'IF')
    DROP function dbo.fn_catch_pending_fish_list
GO
-- fn_catch_pending_fish_list : still-pending species suggestions for a water body
CREATE OR ALTER FUNCTION dbo.fn_catch_pending_fish_list (@lake_id UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT catch_pending_fish_id, catch_pending_fish_name,
           catch_pending_fish_userid, catch_pending_fish_created
    FROM dbo.catch_pending_fish
    WHERE catch_pending_fish_lake_id = @lake_id
      AND catch_pending_fish_status  = 0
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_lake_water_stations' AND xtype = 'IF')
    DROP function dbo.fn_lake_water_stations
GO
-- fn_lake_water_stations : monitoring stations attached to a water body, keyed by
-- WaterStation.lakeId. One water body may carry several stations. Used to draw the 'X'
-- station markers on the river-viewer map.
-- Called by: FishTracker Resources/wfRiverViewer.aspx.cs (GetWaterStationPoints).
--     SELECT * FROM dbo.fn_lake_water_stations('c21a89df-2892-e811-9104-00155d007b12');
CREATE FUNCTION dbo.fn_lake_water_stations (@lake_id UNIQUEIDENTIFIER)
RETURNS TABLE
AS
RETURN
(
    SELECT sid, mli, lat, lon, locName
    FROM dbo.vWaterStation
    WHERE lakeId = @lake_id
);
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------
