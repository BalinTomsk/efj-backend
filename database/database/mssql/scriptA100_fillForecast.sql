
 -- amount of rules is required for probability 
  update fish      set numRuls=0
  update f set numRuls=1           FROM fish_Rule s, fish f WHERE s.tmL is not null AND  s.tmH is not null AND s.fish_Id=f.fish_Id
  update f set numRuls=2 | numRuls FROM fish_Rule s, fish f WHERE s.tuL is not null AND  s.tuH is not null AND s.fish_Id=f.fish_Id
  update f set numRuls=4 | numRuls FROM fish_Rule s, fish f WHERE s.oxL is not null AND  s.oxH is not null AND s.fish_Id=f.fish_Id
  GO
 -------------------------   create today data for currnt forecast  ---------------------------------------------
delete from CurrentWaterState 
GO 

--select * from CurrentWaterState where mli in (select mli from WaterStation where country='CA' and state='ON')
GO

 insert into CurrentWaterState 
   SELECT temperature, conductance, discharge, turbidity, oxygen, ph, elevation, sid, mli, stamp,  GETUTCDATE() as iterstamp
   FROM USWater.dbo.vUSWaterData WHERE sid in 
      ( SELECT MAX(sid) FROM USWater.dbo.vUSWaterData  WHERE stamp > '20140801' GROUP BY mli )

insert into CurrentWaterState 
   SELECT temperature, conductance, discharge, turbidity, oxygen, ph, elevation, sid, mli, stamp,  GETUTCDATE() as iterstamp
   FROM USWater.dbo.ONCA257 WHERE sid in 
      ( SELECT MAX(sid) FROM USWater.dbo.ONCA257  WHERE stamp > '20011101' GROUP BY mli )  
      AND mli not in (select mli from CurrentWaterState)    
       
GO
update t SET t.temperature=w.temperature, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.vUSWaterData w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND temperature IS NOT NULL GROUP BY mli   )
                             
update t SET t.temperature=w.temperature, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND temperature IS NOT NULL GROUP BY mli   )
                  
update t SET t.turbidity=w.turbidity, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.vUSWaterData w  WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData  WITH (NOLOCK) WHERE ( stamp > '20010101' )
                 AND turbidity IS NOT NULL GROUP BY mli )        
                       
update t SET t.turbidity=w.turbidity, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND turbidity IS NOT NULL GROUP BY mli   )

                 
update t SET t.oxygen=w.oxygen, t.stamp=w.stamp FROM CurrentWaterState t  WITH (NOLOCK), USWater.dbo.vUSWaterData w   WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData  WITH (NOLOCK) WHERE ( stamp > '20010101'  )
                 AND oxygen IS NOT NULL GROUP BY mli )         
    
update t SET t.oxygen=w.oxygen, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND oxygen IS NOT NULL GROUP BY mli   )
    
                      
update t SET t.conductance=w.conductance, t.stamp=w.stamp FROM CurrentWaterState t  WITH (NOLOCK), USWater.dbo.vUSWaterData w   WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData  WITH (NOLOCK) WHERE ( stamp > '20010101'  )
                 AND conductance IS NOT NULL GROUP BY mli ) 
        
update t SET t.conductance=w.conductance, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND conductance IS NOT NULL GROUP BY mli   )
                                  
update t SET t.discharge=w.discharge, t.stamp=w.stamp FROM CurrentWaterState t  WITH (NOLOCK) , USWater.dbo.vUSWaterData w  WITH (NOLOCK) 
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData  WITH (NOLOCK)  WHERE ( stamp > '20010101'  )
                 AND discharge IS NOT NULL GROUP BY mli ) 
      
update t SET t.discharge=w.discharge, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND discharge IS NOT NULL GROUP BY mli   )
                                 
update t SET t.ph=w.ph, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.vUSWaterData w  WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData WITH (NOLOCK) WHERE ( stamp > '20010101'  )
                 AND ph IS NOT NULL GROUP BY mli )    
                  
update t SET t.ph=w.ph, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND ph IS NOT NULL GROUP BY mli   )
                              
update t SET t.elevation=w.elevation, t.stamp=w.stamp 
  FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.vUSWaterData w WITH (NOLOCK) 
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.vUSWaterData WITH (NOLOCK) WHERE ( stamp > '20010101'  )
                 AND elevation IS NOT NULL GROUP BY mli )    
                 
update t SET t.elevation=w.elevation, t.stamp=w.stamp FROM CurrentWaterState t WITH (NOLOCK), USWater.dbo.ONCA257 w WITH (NOLOCK)
    WHERE t.mli=w.mli AND w.sid IN (
   SELECT MAX(sid) FROM USWater.dbo.ONCA257 WITH (NOLOCK) WHERE ( stamp > '20100101' ) AND elevation IS NOT NULL GROUP BY mli   )
                                  
GO

-------------------------   push today's forecast  ------------------------- --------------------
delete from fish_location 
GO
-- initial filling
insert into fish_location (station_Id,  fish_Id ) 
  select w.id as station_Id,  lf.fish_Id 
     from vWaterStation w
	   JOIN lake_fish        lf ON w.lakeId = lf.lake_Id
	   JOIN fish              g ON lf.fish_id = g.fish_id
	   JOIN CurrentWaterState r ON w.mli=r.mli
       WHERE  
--        AND w.state = 'ON' AND country = 'CA'
           ( ((1 & w.locType ) = 1 AND ( 1 & g.water_type ) = 1)     -- lives in lake
           OR  ((2 & w.locType ) = 2 AND ( 2 & g.water_type ) = 2)     -- lives in river
           OR  ((4 & w.locType ) = 4 AND ( 4 & g.water_type ) = 4)     -- lives in stream
           OR  ((8 & w.locType ) = 8 AND ( 8 & g.water_type ) = 8)     -- lives in ponds
           OR  ((16 & w.locType ) = 16 AND ( 16 & g.water_type ) = 16) -- lives in marsh
           OR  ((32 & w.locType ) = 32 AND ( 32 & g.water_type ) = 32)  -- lives in backwater
           OR  ((64 & w.locType ) = 64 AND ( 64 & g.water_type ) = 64)        -- lives in creek
           OR  ((128 & w.locType )= 128 AND ( 128 & g.water_type ) = 128)     -- lives in canal
           OR  ((256 & w.locType )= 256 AND ( 256 & g.water_type ) = 256)     -- lives in Estuary
           OR  ((512 & w.locType )= 512 AND ( 512 & g.water_type ) = 512)     -- lives in shore
           OR  ((1024 & w.locType )= 1024 AND ( 1024 & g.water_type ) = 1024) -- lives in drain
--           OR  ((2048 & w.locType )= 2048 AND ( 2048 & f.water_type ) = 2048) -- lives in ocean
           OR  ((4096 & w.locType )= 4096 AND ( 4096 & g.water_type ) = 4096)-- lives in Wetland
--           OR  ((8192 & w.locType )= 8192 AND ( 8192 & f.habitat ) = 8192)-- lives in Reservoir
           OR  ((16384 & w.locType )= 16384 AND ( 16384 & g.water_type ) = 16384)-- lives in Dam
           OR  ((32768 & w.locType )= 32768 AND ( 32768 & g.water_type ) = 32768))-- lives in falls
         AND EXISTS (SELECT *  FROM fish_Rule r WHERE g.fish_Id=r.fish_Id)    -- AND f.water <> 1
GO
 ---- 1 - temperature, 2 - turbidity, 4 - oxygen 
 select * from vWaterStation

-- EXEC dbo.spPushSpeciesFromLakeToStation

-- select * from vGetFishingStation100TmTu
--select MAX(temperature), MIN(temperature) from CurrentWaterState
--select * from CurrentWaterState


--select * from vGetFishingStation100Tm
--select * from vFishRulesTm


--select * from vGetFishingStation100Tu
--select * from vFishRulesTmTu
--select * from  dbo.SpeciesRules where fishid in (select ID from dbo.Species where name='Lake Chubsucker')
--update SpeciesRules set tuL = NULL, tuH=NULL where fishid in (select ID from dbo.Species where name='Bull trout')


--------------------------------------  distance  -----------------------------------

-- home service get data from cmd
CREATE PROCEDURE sp_weather_forecast16 @city_id int, @mli varchar(64),  @event int
       , @temp_day float, @temp_min float, @temp_max float, @temp_night float, @temp_eve float, @temp_morn float
	   , @pressure float, @humidity float, @main varchar(64), @description varchar(255), @icon varchar(32)
       , @speed float, @degree int, @clouds int , @rain float
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
 	DECLARE @direction varchar(8) = ( SELECT dbo.fn_direction_by_degree( @degree ) )
	DECLARE @weather_temperature smallint = ROUND(@temp_day, 0)
	
	SELECT @weather_temperature = ROUND( ( CASE WHEN DATEPART( HOUR, @tm ) BETWEEN 4 AND 11 THEN @temp_morn
	           WHEN DATEPART( HOUR, @tm ) BETWEEN 11 AND 16 THEN @temp_day
			   WHEN DATEPART( HOUR, @tm ) BETWEEN 16 AND 23 THEN @temp_eve
			   ELSE @temp_night END ), 0 );
	
	IF @dt = CAST(getdate() AS DATE)  
	BEGIN
		INSERT dbo.weather_Forecast( city_id,  mli, tmHigh,     tmLow,     tmDay,        humidity,  pressure, maxWin,  degree, rain_today,    direction,  dt,  tm, icon, shortText, longText, weather_temperature )
			VALUES ( @city_id, @mli, @temp_max, @temp_min, @temp_day, @humidity, @pressure, @speed, @degree, @rain, @direction, @dt, @tm, @icon, @main, @description, @weather_temperature )
    END
		ELSE IF @dt > CAST(getdate() AS DATE)  
	BEGIN
		DELETE FROM weather_Forecast WHERE dt = @dt AND mli = @mli

		INSERT dbo.weather_Forecast( city_id,  mli, tmHigh,     tmLow,     tmDay,        humidity,  pressure, maxWin,  degree, rain_today,    direction,  dt,  tm, icon, shortText, longText, weather_temperature )
			VALUES ( @city_id, @mli, @temp_max, @temp_min, @temp_day, @humidity, @pressure, @speed, @degree, @rain, @direction, @dt, @tm, @icon, @main, @description, @weather_temperature )
	END
    RETURN @@ROWCOUNT;
END TRY
BEGIN CATCH
    SELECT
         ERROR_NUMBER()    AS ErrorNumber
        ,ERROR_SEVERITY()  AS ErrorSeverity
        ,ERROR_STATE()     AS ErrorState
        ,ERROR_PROCEDURE() AS ErrorProcedure
        ,ERROR_LINE()      AS ErrorLine
        ,ERROR_MESSAGE()   AS ErrorMessage;
END CATCH; 	     
