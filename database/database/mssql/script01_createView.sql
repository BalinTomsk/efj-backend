
-------------------------------------  Lake --------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vGetLake' AND type = 'V')
    DROP VIEW dbo.vGetLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_only_river_list' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_only_river_list
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_list' AND xtype = 'TF')
    DROP FUNCTION dbo.fn_river_list
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_full_resource_list' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_full_resource_list
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetCloseLake' AND type = 'IF')
    DROP FUNCTION dbo.fn_GetCloseLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetLakeRegulations' AND type = 'IF')
    DROP FUNCTION dbo.fn_GetLakeRegulations
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeStates' AND type = 'IF')
    DROP FUNCTION dbo.fn_GetAllLakeStates
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_GetAllLakeZones' AND type = 'IF')
    DROP FUNCTION dbo.fn_GetAllLakeZones
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_ViewTributary' AND type = 'TF')
    DROP FUNCTION dbo.fn_ViewTributary
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_list' AND type = 'IF')
    DROP FUNCTION dbo.fn_river_list
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_river_sym' AND xtype = 'IF')
    DROP function dbo.fn_river_sym
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_lake' AND type = 'V')
    DROP VIEW dbo.vw_lake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vDefaultLastLake' AND type = 'V')
    DROP VIEW dbo.vDefaultLastLake
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_CombineLocation' AND xtype = 'FN')
    DROP function dbo.fn_CombineLocation
GO
-- gives suggested fished for LakeFish Editor
-- SELECT dbo.fn_CombineLocation( 'district', 'region', 'municipality', 'county', 'city', 'location' )
-- SELECT dbo.fn_CombineLocation( null, 'region', 'municipality', 'county', 'city', 'location' )
-- SELECT dbo.fn_CombineLocation( null, 'region', null, 'county', null, null )
-- SELECT dbo.fn_CombineLocation( null, 'region', 'region', 'county', null, null )
-- SELECT dbo.fn_CombineLocation( null, null, null, null, null, null )
CREATE function dbo.fn_CombineLocation( @district nvarchar(64), @region nvarchar(64), @municipality nvarchar(64), @county nvarchar(64), @city nvarchar(64), @location nvarchar(64) )
returns sysname
WITH SCHEMABINDING
as
begin
    DECLARE @result nvarchar(2048) = ''

    SELECT @result = @result + '>' + val FROM 
    (
        SELECT val, rn FROM(
            select TOP 6 val, rn=row_number() over (partition by val order by id), id  from  
            (
                SELECT val, id FROM 
                    ( SELECT NULLIF(LTRIM(RTRIM(value)), '') AS val, id 
                        FROM ( VALUES (@district, 1), (@region, 2), (@municipality, 3), (@county, 4), (@city, 5), (@location, 6) )x(value, id) )y
                    WHERE val IS NOT NULL 
            )z ORDER BY id ASC)v WHERE rn = 1
    )y
    RETURN (CASE WHEN @result IS NULL OR LEN(@result) < 2 THEN @result ELSE RIGHT(@result, LEN(@result)-1) END);
END
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
---- SELECT * FROM dbo.vw_lake WHERE lake_id = '45c0706e-d3aa-47eb-80b1-3f4712817916'
---- SELECT * FROM dbo.vw_lake WHERE state='ON' and LEFT(lake_name,1)= 'A'	
---- select * from vw_lake where lake_name = 'Seguin River' AND state='ON' 
---- select * from lake where reviewed = 1
CREATE VIEW dbo.vw_lake
WITH SCHEMABINDING
AS 
    SELECT source_name, mouth_name, isWell, isFish
        , lake_id, lake_name, symbol
		, CASE WHEN alt_name = lake_name THEN null ELSE alt_name END AS alt_name
		, native_name
		, french_name
		, old_id, length, depth, width, locType
        , basin, watershield, link, locked, editor, descript, Volume, Shoreline, Drainage, surface
        , source_id
        , source_Elevation, source_Lat, source_Lon, source_region, source_municipality, source_location
        , source_state, source_country, source_county, source_city, source_district, source_zone, source_description
        , mouth_id
        , mouth_Elevation, mouth_Lat, mouth_Lon, mouth_region, mouth_municipality, mouth_location
        , mouth_state, mouth_country, mouth_county, mouth_city, mouth_district, mouth_zone, mouth_description
        , lat, lon, city, county, state, country, region, district, municipality, zone, Discharge, fishing, CGNDB
        , lake_image_source, lake_image_author, lake_image_link, lake_image_stamp
        , COALESCE(source_loc, mouth_loc)    AS location, source_loc, mouth_loc
		, IIF(t_stamp > stamp, t_stamp, stamp) AS stamp, road_access, reviewed
        FROM 
    (
     SELECT CASE WHEN l.lake_name <> source.lake_name THEN source.lake_name ELSe NULL END AS source_name
        ,  CASE WHEN l.lake_name <> mouth.lake_name  THEN mouth.lake_name  ELSe NULL END AS mouth_name
        , l.lake_id, l.lake_name, COALESCE(l.alt_name, l.native) AS alt_name, l.old_id, l.length, l.depth, l.width, l.locType
        , l.basin, l.watershield, l.link, l.locked, l.editor, l.descript, l.Volume, l.Shoreline, l.Drainage, l.surface
        , l.Discharge, l.isfish, l.fishing, l.CGNDB, l.native AS native_name, l.isWell, l.symbol
		, CASE WHEN l.french_name = l.lake_name THEN null ELSE l.french_name END AS french_name
        , COALESCE(l.source, CASE WHEN s.lake_id <> l.lake_id THEN s.lake_id ELSE NULL END) AS source_id
        , s.Elevation AS source_Elevation, s.lat AS source_Lat, s.lon AS source_Lon, s.region AS source_region, s.municipality AS source_municipality, s.location AS source_location
        , s.state AS source_state, s.country AS source_country, s.county as source_county, s.city as source_city, s.district as source_district, s.zone as source_zone, s.descript AS source_description
        , COALESCE(l.mouth, CASE WHEN m.lake_id <> l.lake_id THEN m.lake_id ELSE NULL END) AS mouth_id
        , m.Elevation AS mouth_Elevation, m.Lat AS mouth_Lat, m.Lon AS mouth_Lon, m.region AS mouth_region, m.municipality AS mouth_municipality, m.location AS mouth_location
        , m.state AS mouth_state, m.country AS mouth_country, m.county AS mouth_county, m.city AS mouth_city, m.district AS mouth_district, m.zone AS mouth_zone, m.descript AS mouth_description
        , CASE WHEN s.Lat IS NOT NULL AND m.Lat Is NOT NULL THEN ABS(s.Lat-m.Lat) / 2.0 + (CASE WHEN s.Lat < m.Lat THEN s.Lat ELSE m.Lat END) ELSE COALESCE(s.Lat, m.Lat) END AS lat
        , CASE WHEN s.Lon IS NOT NULL AND m.Lon Is NOT NULL THEN ABS(s.Lon-m.Lon) / 2.0 + (CASE WHEN s.Lon < m.Lon THEN s.Lon ELSE m.Lon END) ELSE COALESCE(s.Lon, m.Lon) END AS lon
        , dbo.fn_CombineLocation( s.district, s.region, s.municipality, s.county, s.city, s.location )      AS source_loc
        , dbo.fn_CombineLocation( m.district,  m.region,  m.municipality,  m.county,  m.city,  m.location ) AS mouth_loc
        , COALESCE(RTRIM(s.city),         RTRIM(m.city))     AS city
        , COALESCE(RTRIM(s.county),       RTRIM(m.county))   AS county
        , COALESCE(RTRIM(s.state),        RTRIM(m.state))    AS state
        , COALESCE(RTRIM(s.country),      RTRIM(m.country))  AS country
        , COALESCE(RTRIM(s.region),       RTRIM(m.region))   AS region
        , COALESCE(RTRIM(s.district),     RTRIM(m.district)) AS district
        , COALESCE(RTRIM(s.municipality), RTRIM(m.municipality)) AS municipality
        , COALESCE(RTRIM(s.zone), RTRIM(m.zone)) AS zone
        , i.lake_image_source, i.lake_image_author, i.lake_image_link, i.lake_image_stamp, l.stamp
		, IIF( COALESCE(m.Tributaries_stamp, '20010101') > COALESCE(s.Tributaries_stamp, '20010101') , COALESCE(m.Tributaries_stamp, '20010101'), COALESCE(s.Tributaries_stamp, '20010101')) AS t_stamp
        , CASE WHEN l.lake_road_access In (s.district, m.district) THEN NULL ELSE l.lake_road_access END AS road_access, l.reviewed
        FROM dbo.lake l  
            JOIN dbo.Tributaries m ON m.main_lake_id = l.lake_id AND m.side = 32    -- only single source
            JOIN dbo.Tributaries s ON s.main_lake_id = l.lake_id AND s.side = 16    -- only single mouth
            LEFT JOIN dbo.lake mouth  ON mouth.lake_id  = m.lake_id
            LEFT JOIN dbo.lake source ON source.lake_id = s.lake_id
            LEFT JOIN dbo.lake_image i ON i.lake_image_ownerid = l.lake_id
   )x
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_lake_state' AND xtype = 'V')
    DROP VIEW dbo.vw_lake_state
GO

/*
	SELECT * FROM vw_lake_state WHERE lake_id = '56A589E1-2892-E811-9104-00155D007B12'
*/
CREATE VIEW dbo.vw_lake_state
WITH SCHEMABINDING
AS
	SELECT l.lake_id, lake_name, s.Stamp
			, s.pH, s.phosphorus, TDS, Conductivity, Alkalinity, Hardness, Sodium, Chloride, Bicarbonate
			, transparency, oxygen, Salinity, clarity, s.velocity, [month]
			FROM dbo.Lake_State s JOIN dbo.lake l ON l.lake_id = s.lake_id
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_koef_fish_station_oxygen' AND xtype = 'V')
    DROP VIEW dbo.fn_get_koef_fish_station_oxygen
GO

CREATE VIEW dbo.fn_get_koef_fish_station_oxygen
WITH SCHEMABINDING
AS 
  WITH cte ( fish_id, fish_name, oxL, oxH ) AS          
  (                                                                         -- 80% 90%    100%         90%
     SELECT  f.fish_id, f.fish_name, ox.ri_min, ox.ri_max                   ---|   |  |__optimum______|  |
       FROM  dbo.fish f JOIN dbo.fish_Rule r ON ( r.fish_Id=f.fish_id )     ---|   |__________________|  |
       JOIN dbo.real_interval ox ON ox.ri_parent_id = r.id AND ox.ri_type = 33
       WHERE r.periodStart = -1 AND r.periodEnd = -1                        ---|_________________________|
  )
    SELECT mli, fish_ID, koef FROM 
    (
        SELECT mli, fish_ID, 0 AS value, ox, oxL, oxH                        -- all data exists
        , CASE WHEN ox BETWEEN l100 AND h90  THEN 1.0 
                WHEN (ox BETWEEN l90 AND l100) OR (ox BETWEEN h90 AND oxH) THEN 0.9
                WHEN (ox BETWEEN oxL AND l90) THEN 0.8 ELSE 0.5 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ox, oxL, oxH
                , (oxL + (( optimum - oxL )  /  2)) AS l100
                , (optimum + (( oxH - optimum ) / 4))  AS h90,  (oxL + (( optimum - oxL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, oxygen AS ox, oxL, oxH, (( oxH - oxL ) / 2) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND oxL Is NOT NULL AND oxH Is NOT NULL
            )b
        ) a
        UNION ALL
        SELECT mli, fish_ID, 1 AS value, ox, oxL, oxH                          --- oxL Is NULL
        , CASE WHEN ox BETWEEN l100 AND h90  THEN 1.0 
                WHEN (ox BETWEEN l90 AND l100) OR (ox BETWEEN h90 AND oxH) THEN 0.9
                WHEN (ox BETWEEN oxL AND l90) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ox, oxL, oxH
                , (optimum + (( oxH - optimum ) / 2))  AS h100, (oxL + (( optimum - oxL )  /  2)) AS l100
                , (optimum + (( oxH - optimum ) / 4))  AS h90,  (oxL + (( optimum - oxL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, oxygen as ox, (oxH / 2) as oxL, oxH, (oxH / 2) + (oxH / 4) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND oxL Is NULL AND oxH Is NOT NULL
            )d
        ) c
        UNION ALL
        SELECT mli, fish_ID, 2 AS value, ox, oxL, oxH
        , CASE WHEN ox BETWEEN l100 AND h90  THEN 1.0 
                WHEN (ox BETWEEN l90 AND l100) OR (ox BETWEEN h90 AND oxH) THEN 0.9
                WHEN (ox BETWEEN oxL AND l90) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ox, oxL, oxH
                , (optimum + (( oxH - optimum ) / 2))  AS h100, (oxL + (( optimum - oxL )  /  2)) AS l100
                , (optimum + (( oxH - optimum ) / 4))  AS h90,  (oxL + (( optimum - oxL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, oxygen as ox,  oxL, (oxL + 10) as oxH, (oxL + 5) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND oxL IS NOT NULL AND oxH IS NULL
            )e
        ) f
        UNION ALL
        SELECT mli, fish_ID, 3 AS value, oxygen as ox,  oxL, oxH, 1 AS koef
                FROM cte, dbo.CurrentWaterState w 
            where w.temperature IS NULL
    ) g WHERE value = CASE 
          WHEN ox IS NULL OR ( ox IS NOT NULL AND oxL IS NULL AND oxH IS NULL )THEN 3
          WHEN ox IS NOT NULL AND oxL IS NULL AND oxH IS NOT NULL THEN 1 
          WHEN ox IS NOT NULL AND oxL IS NOT NULL AND oxH IS NULL THEN 2 
          WHEN ox IS NOT NULL AND oxL IS NOT NULL AND oxH IS NOT NULL THEN 0 
        END AND koef IS NOT NULL

GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_koef_fish_station_ph' AND xtype = 'V')
    DROP VIEW dbo.fn_get_koef_fish_station_ph
GO

CREATE VIEW dbo.fn_get_koef_fish_station_ph
WITH SCHEMABINDING
AS 
  WITH cte ( fish_id, fish_name, phL, phH ) AS
  (                                                                         -- 80% 90%    100%     90% 80%
     SELECT  f.fish_id, f.fish_name, habitate_ph.ri_min AS phL              ---|   |  |__optimum___|  |  |
           , habitate_ph.ri_max AS phH                           
       FROM  dbo.fish f JOIN dbo.fish_Rule r ON ( r.fish_Id=f.fish_id )     ---|   |__________________|  |
                                                                            ---|_________________________|
       JOIN dbo.real_interval habitate_ph ON habitate_ph.ri_parent_id = r.id AND habitate_ph.ri_type = 9
       WHERE r.periodStart = -1 AND r.periodEnd = -1                        
  )
    SELECT mli, fish_ID, koef FROM 
    (
        SELECT mli, fish_ID, 0 AS value, ph, phL, phH                        -- all data exists
        , CASE WHEN ph BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ph BETWEEN l90 AND l100) OR (ph BETWEEN h100 AND h90) THEN 0.9
                WHEN (ph BETWEEN phL AND l90)  OR (ph BETWEEN h90 AND  phH) THEN 0.8 ELSE 0.5 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ph, phL, phH
                , (optimum + (( phH - optimum ) / 2))  AS h100, (phL + (( optimum - phL )  /  2)) AS l100
                , (optimum + (( phH - optimum ) / 4))  AS h90,  (phL + (( optimum - phL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, ph AS ph, phL, phH, (( phH - phL ) / 2) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.ph IS NOT NULL AND phL Is NOT NULL AND phH Is NOT NULL
            )b
        ) a
        UNION ALL
        SELECT mli, fish_ID, 1 AS value, ph, phL, phH                          --- phL Is NULL
        , CASE WHEN ph BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ph BETWEEN l90 AND l100) OR (ph BETWEEN h100 AND h90) THEN 0.9
                WHEN (ph BETWEEN phL AND l90)  OR (ph BETWEEN h90 AND  phH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ph, phL, phH
                , (optimum + (( phH - optimum ) / 2))  AS h100, (phL + (( optimum - phL )  /  2)) AS l100
                , (optimum + (( phH - optimum ) / 4))  AS h90,  (phL + (( optimum - phL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, ph as ph, (phH / 2) as phL, phH, (phH / 2) + (phH / 4) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.ph IS NOT NULL AND phL Is NULL AND phH Is NOT NULL
            )d
        ) c
        UNION ALL
        SELECT mli, fish_ID, 2 AS value, ph, phL, phH
        , CASE WHEN ph BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ph BETWEEN l90 AND l100) OR (ph BETWEEN h100 AND h90) THEN 0.9
                WHEN (ph BETWEEN phL AND l90)  OR (ph BETWEEN h90 AND  phH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ph, phL, phH
                , (optimum + (( phH - optimum ) / 2))  AS h100, (phL + (( optimum - phL )  /  2)) AS l100
                , (optimum + (( phH - optimum ) / 4))  AS h90,  (phL + (( optimum - phL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, ph as ph,  phL, (phL + 10) as phH, (phL + 5) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.ph IS NOT NULL AND phL IS NOT NULL AND phH IS NULL
            )e
        ) f
        UNION ALL
        SELECT mli, fish_ID, 3 AS value, ph as ph,  phL, phH, 1 AS koef
                FROM cte, dbo.CurrentWaterState w 
            where w.ph IS NULL
    ) g WHERE value = CASE 
          WHEN ph IS NULL OR ( ph IS NOT NULL AND phL IS NULL AND phH IS NULL )THEN 3
          WHEN ph IS NOT NULL AND phL IS NULL AND phH IS NOT NULL THEN 1 
          WHEN ph IS NOT NULL AND phL IS NOT NULL AND phH IS NULL THEN 2 
          WHEN ph IS NOT NULL AND phL IS NOT NULL AND phH IS NOT NULL THEN 0 
        END AND koef IS NOT NULL
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_koef_fish_station_temperature' AND xtype = 'V')
    DROP VIEW dbo.fn_get_koef_fish_station_temperature
GO
CREATE VIEW dbo.fn_get_koef_fish_station_temperature
WITH SCHEMABINDING
AS 
  WITH cte ( fish_id, fish_name, tmL, tmH ) AS
  (                                                                         -- 80% 90%    100%     90% 80%
     SELECT f.fish_id, f.fish_name, habitate_tm.ri_min AS tmL               ---|   |  |__optimum___|  |  |
          , habitate_tm.ri_max AS tmH                                       ---|   |__________________|  |  
       FROM  dbo.fish f JOIN dbo.fish_Rule r ON ( r.fish_Id=f.fish_id )     ---|_________________________|
       JOIN dbo.real_interval habitate_tm ON habitate_tm.ri_parent_id = r.id AND habitate_tm.ri_type = 17
       WHERE r.periodStart = -1 AND r.periodEnd = -1                        
  )
    SELECT mli, fish_ID, koef FROM 
    (
        SELECT mli, fish_ID, 0 AS value, tm, tmL, tmH                        -- all data exists
        , CASE WHEN tm BETWEEN l100 AND h100  THEN 1.0 
                WHEN (tm BETWEEN l90 AND l100) OR (tm BETWEEN h100 AND h90) THEN 0.9
                WHEN (tm BETWEEN tmL AND l90)  OR (tm BETWEEN h90 AND  tmH) THEN 0.8 ELSE 0.5 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, tm, tmL, tmH
                , (optimum + (( tmH - optimum ) / 2))  AS h100, (tmL + (( optimum - tmL )  /  2)) AS l100
                , (optimum + (( tmH - optimum ) / 4))  AS h90,  (tmL + (( optimum - tmL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, temperature AS tm, tmL, tmH, (( tmH - tmL ) / 2) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND tmL Is NOT NULL AND tmH Is NOT NULL
            )b
        ) a
        UNION ALL
        SELECT mli, fish_ID, 1 AS value, tm, tmL, tmH                          --- tmL Is NULL
        , CASE WHEN tm BETWEEN l100 AND h100  THEN 1.0 
                WHEN (tm BETWEEN l90 AND l100) OR (tm BETWEEN h100 AND h90) THEN 0.9
                WHEN (tm BETWEEN tmL AND l90)  OR (tm BETWEEN h90 AND  tmH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, tm, tmL, tmH
                , (optimum + (( tmH - optimum ) / 2))  AS h100, (tmL + (( optimum - tmL )  /  2)) AS l100
                , (optimum + (( tmH - optimum ) / 4))  AS h90,  (tmL + (( optimum - tmL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, temperature as tm, (tmH / 2) as tmL, tmH, (tmH / 2) + (tmH / 4) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND tmL Is NULL AND tmH Is NOT NULL
            )d
        ) c
        UNION ALL
        SELECT mli, fish_ID, 2 AS value, tm, tmL, tmH
        , CASE WHEN tm BETWEEN l100 AND h100  THEN 1.0 
                WHEN (tm BETWEEN l90 AND l100) OR (tm BETWEEN h100 AND h90) THEN 0.9
                WHEN (tm BETWEEN tmL AND l90)  OR (tm BETWEEN h90 AND  tmH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, tm, tmL, tmH
                , (optimum + (( tmH - optimum ) / 2))  AS h100, (tmL + (( optimum - tmL )  /  2)) AS l100
                , (optimum + (( tmH - optimum ) / 4))  AS h90,  (tmL + (( optimum - tmL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, temperature as tm,  tmL, (tmL + 10) as tmH, (tmL + 5) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.temperature IS NOT NULL AND tmL IS NOT NULL AND tmH IS NULL
            )e
        ) f
        UNION ALL
        SELECT mli, fish_ID, 3 AS value, temperature as tm,  tmL, tmH, 1 AS koef
                FROM cte, dbo.CurrentWaterState w 
            where w.temperature IS NULL
    ) g WHERE value = CASE 
          WHEN tm IS NULL OR ( tm IS NOT NULL AND tmL IS NULL AND tmH IS NULL )THEN 3
          WHEN tm IS NOT NULL AND tmL IS NULL AND tmH IS NOT NULL THEN 1 
          WHEN tm IS NOT NULL AND tmL IS NOT NULL AND tmH IS NULL THEN 2 
          WHEN tm IS NOT NULL AND tmL IS NOT NULL AND tmH IS NOT NULL THEN 0 
        END AND koef IS NOT NULL
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_koef_fish_station_velocity' AND xtype = 'V')
    DROP VIEW dbo.fn_get_koef_fish_station_velocity
GO
CREATE VIEW dbo.fn_get_koef_fish_station_velocity
WITH SCHEMABINDING
AS 
  WITH cte ( fish_id, fish_name, veL, veH ) AS
  (                                                                         -- 80% 90%    100%     90% 80%
     SELECT  f.fish_id, f.fish_name, ve.ri_min AS veL, ve.ri_max AS veH     ---|   |  |__optimum___|  |  |
       FROM  dbo.fish f JOIN dbo.fish_Rule r ON ( r.fish_Id=f.fish_id )     ---|   |__________________|  |
       JOIN dbo.real_interval ve ON ve.ri_parent_id = r.id AND ve.ri_type = 41
       WHERE r.periodStart = -1 AND r.periodEnd = -1                        ---|_________________________|
  )
    SELECT mli, fish_ID, koef FROM 
    (
        SELECT mli, fish_ID, 0 AS value, ve, veL, veH                        -- all data exists
        , CASE WHEN ve BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ve BETWEEN l90 AND l100) OR (ve BETWEEN h100 AND h90) THEN 0.9
                WHEN (ve BETWEEN veL AND l90)  OR (ve BETWEEN h90 AND  veH) THEN 0.8 ELSE 0.5 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ve, veL, veH
                , (optimum + (( veH - optimum ) / 2))  AS h100, (veL + (( optimum - veL )  /  2)) AS l100
                , (optimum + (( veH - optimum ) / 4))  AS h90,  (veL + (( optimum - veL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, velocity AS ve, veL, veH, (( veH - veL ) / 2) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.velocity IS NOT NULL AND veL Is NOT NULL AND veH Is NOT NULL
            )b
        ) a
        UNION ALL
        SELECT mli, fish_ID, 1 AS value, ve, veL, veH                          --- veL Is NULL
        , CASE WHEN ve BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ve BETWEEN l90 AND l100) OR (ve BETWEEN h100 AND h90) THEN 0.9
                WHEN (ve BETWEEN veL AND l90)  OR (ve BETWEEN h90 AND  veH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ve, veL, veH
                , (optimum + (( veH - optimum ) / 2))  AS h100, (veL + (( optimum - veL )  /  2)) AS l100
                , (optimum + (( veH - optimum ) / 4))  AS h90,  (veL + (( optimum - veL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, velocity as ve, (veH / 2) as veL, veH, (veH / 2) + (veH / 4) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.velocity IS NOT NULL AND veL Is NULL AND veH Is NOT NULL
            )d
        ) c
        UNION ALL
        SELECT mli, fish_ID, 2 AS value, ve, veL, veH
        , CASE WHEN ve BETWEEN l100 AND h100  THEN 1.0 
                WHEN (ve BETWEEN l90 AND l100) OR (ve BETWEEN h100 AND h90) THEN 0.9
                WHEN (ve BETWEEN veL AND l90)  OR (ve BETWEEN h90 AND  veH) THEN 0.8 END AS koef
        FROM 
        (
            SELECT mli, fish_ID, ve, veL, veH
                , (optimum + (( veH - optimum ) / 2))  AS h100, (veL + (( optimum - veL )  /  2)) AS l100
                , (optimum + (( veH - optimum ) / 4))  AS h90,  (veL + (( optimum - veL )  /  4)) AS l90
            FROM
            (
                SELECT mli, fish_ID, velocity as ve,  veL, (veL + 10) as veH, (veL + 5) AS optimum
                FROM cte, dbo.CurrentWaterState w 
                    where w.velocity IS NOT NULL AND veL IS NOT NULL AND veH IS NULL
            )e
        ) f
        UNION ALL
        SELECT mli, fish_ID, 3 AS value, velocity as ve,  veL, veH, 1 AS koef
                FROM cte, dbo.CurrentWaterState w 
            where w.velocity IS NULL
    ) g WHERE value = CASE 
          WHEN ve IS NULL OR ( ve IS NOT NULL AND veL IS NULL AND veH IS NULL )THEN 3
          WHEN ve IS NOT NULL AND veL IS NULL AND veH IS NOT NULL THEN 1 
          WHEN ve IS NOT NULL AND veL IS NOT NULL AND veH IS NULL THEN 2 
          WHEN ve IS NOT NULL AND veL IS NOT NULL AND veH IS NOT NULL THEN 0 
        END AND koef IS NOT NULL
GO
-------------------------------------  bool TReading::LoadFromDb(const wchar_t* wzConnStr) --------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vCurrentWaterState' AND type = 'V')
    DROP VIEW dbo.vCurrentWaterState
GO
CREATE VIEW vCurrentWaterState 
WITH SCHEMABINDING
AS 
  SELECT mli, stamp, CAST(temperature AS char(16)) as temperature
  , CAST(discharge AS char(16)) as discharge
  , CAST(turbidity AS char(16)) as turbidity
  , CAST(oxygen AS char(16)) as oxygen
  , CAST(ph AS char(16)) as ph
  , CAST(elevation AS char(16)) as elevation 
  , iterstamp
  FROM dbo.CurrentWaterState WITH (NOLOCK)
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vFishOK' AND type = 'V')
    DROP VIEW dbo.vFishOK
GO

CREATE VIEW dbo.vFishOK AS 
select fish_name, fish_latin, fish_id,
  CASE WHEN CHARINDEX(',', fish_name ) > 0 THEN (LTRIM(RIGHT(fish_name, LEN(fish_name)-CHARINDEX(',', fish_name ) - 1)) + ' ' + RTRIM(LEFT(fish_name, CHARINDEX(',', fish_name )-1)))
   ELSE fish_name END AS name  from fish
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_fish_bylatlon
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vget_fish_list' AND type = 'V')
    DROP VIEW dbo.vget_fish_list
GO

CREATE VIEW dbo.vget_fish_list
WITH SCHEMABINDING
AS 
  SELECT  fish_Id, fish_name  FROM dbo.FISH 
     WHERE ( fish_Type & 1 ) = 1                   --- sport species
GO
-- select * from dbo.vget_fish_list  order by 2
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_byzip' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_byzip
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_fish_bylatlon' AND xtype = 'IF')
    DROP FUNCTION dbo.fn_get_trial_fish_bylatlon
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vget_trial_fish_list' AND type = 'V')
    DROP VIEW dbo.vget_trial_fish_list
GO
-- fn_get_trial_fish_bylatlon, fn_get_trial_fish_byzip
-- 1 - sport, 2 - Coarse, 4 - commersial, 8 - invading
CREATE  VIEW dbo.vget_trial_fish_list
WITH SCHEMABINDING
AS 
  SELECT f. fish_Id,  fish_name  
     FROM dbo.fish f JOIN dbo.fish_zoo z ON f.fish_id=z.fish_id
     WHERE NOT ( fish_Type & 1 = 1 OR fish_Type & 2 = 2) AND z.fish_max_length BETWEEN 40 AND 70   
GO
-- select *  from  dbo.vget_trial_fish_list
-- 1 - sport, 2 - Coarse, 4 - commersial, 8 - invading, 128 - migrate pattern (inverted logic by default)
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vGetCurrentWeather' AND type = 'V')
    DROP VIEW dbo.vGetCurrentWeather
GO  
CREATE VIEW dbo.vGetCurrentWeather
-- WITH SCHEMABINDING
 AS
    SELECT dt, wind_degree, gpfDay, gpfNight, humidity, wind_direction
    , tmLow, tmHigh, wind_max_speed, shortText, longText, icon, w.sid as sid
      FROM dbo.weather_Forecast f 
        JOIN dbo.WaterStation w on f.link=w.id WHERE tm IS NULL AND dt >= CONVERT(VARCHAR(10),GETDATE(),101)   
GO
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vGetOntarioList' AND xtype = 'V')
    DROP VIEW dbo.vGetOntarioList 
GO
CREATE VIEW dbo.vGetOntarioList
AS  
  SELECT * FROM dbo.WaterStation WITH (NOLOCK) WHERE country = 'CA'
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vCurrentWaterState' AND type = 'V')
    DROP VIEW dbo.vCurrentWaterState
GO

CREATE VIEW dbo.vCurrentWaterState
WITH SCHEMABINDING
AS 
  SELECT mli, stamp, CAST(temperature AS char(16)) as temperature
  , CAST(discharge AS char(16)) as discharge
  , CAST(turbidity AS char(16)) as turbidity
  , CAST(oxygen AS char(16)) as oxygen
  , CAST(ph AS char(16)) as ph
  , CAST(elevation AS char(16)) as elevation 
  , iterstamp
  FROM dbo.CurrentWaterState WITH (NOLOCK)
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vMapView' AND type = 'V')
    DROP VIEW dbo.vMapView
GO
-- SELECT  TOP 1000  lat, lon, sid FROM vMapView WHERE country='CA'
-- SELECT  * FROM vMapView WHERE country='US' and cast(stamp as date) > '2020-01-01'


CREATE VIEW dbo.vMapView 
WITH SCHEMABINDING
 AS
	SELECT w.sid, w.lat, w.lon, w.country, w.state, y.stamp FROM dbo.WaterStation w WITH (NOLOCK) 
		JOIN
		(
			SELECT TOP 16024 sid, stamp FROM dbo.CurrentWaterState d WITH (NOLOCK) WHERE stamp > dateadd(day, -15, getdate()) and sid > 0
			UNION
			SELECT sid, stamp FROM (SELECT TOP 16024 sid, stamp FROM dbo.CurrentWaterState d WITH (NOLOCK) WHERE sid > 0 ORDER BY  getdate() DESC)x
		)y ON w.sid=y.sid
		WHERE state NOT IN ('HI', 'PR') 
		--AND EXISTS (SELECT mli FROM [dbo].[WaterData] d WHERE d.mli =w.mli)
GO

------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLastHourWaterData' AND xtype = 'IF')
    DROP function dbo.GetLastHourWaterData
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vScienceView' AND type = 'V')
    DROP VIEW dbo.vScienceView
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_WaterData' AND type = 'V')
    DROP VIEW dbo.vw_WaterData
GO
--- hide internal convertions: PH, airtemp
-- select top 100  * from vw_WaterData where dt > '2021-01-01'
--   select top 100  * from vw_WaterData  where  mli = '02GE004' or  263911 = sid
CREATE VIEW dbo.vw_WaterData
WITH SCHEMABINDING
 AS
    SELECT w.mli, w.state, w.lat, w.lon, w.id, w.sid, w.locName, w.city, w.country, d.stamp
        , CAST(d.stamp AS date) AS dt
		, CAST(CAST(DATEADD(HOUR,w.tz, d.stamp) AS time) AS varchar(8)) AS tm
		, temperature, discharge
        , d.elevation, (CAST(d.ph AS float) / 10.0) AS PH, d.oxygen, d.turbidity, velocity
    FROM dbo.WaterStation w JOIN dbo.WaterData d ON d.mli = w.mli
GO

------------------------------------------------------------------------------
-- select TOP 1 * from dbo.vScienceView WHERE 263911 = sid order by dt desc, tm desc
------------------------------------------------------------------------------

CREATE VIEW dbo.vScienceView 
WITH SCHEMABINDING
 AS
SELECT mli, state, lat, lon, id, sid, locName, city, country, stamp
   , CONVERT(varchar(16), dt, 107) AS dt, CAST(tm AS varchar(5)) AS tm
   , ISNULL( CAST(ROUND(temperature, 1) AS varchar(16)), 'N/A') AS temperature
   , ( CASE WHEN country = 'US' THEN 'F' ELSE 'C' END ) AS temperature_unit
   , ISNULL( CAST(NULLIF(ROUND(discharge, 1), 0) AS varchar(16)), 'N/A') AS discharge
   , ( CASE WHEN country = 'US' THEN 'ft^3/s' ELSE 'm^3/s' END ) AS discharge_unit
   , ISNULL( CAST(ROUND(elevation, 2) AS varchar(16)), 'N/A') AS elevation
   , ( CASE WHEN country = 'US' THEN 'ft' ELSE 'm' END ) AS elevation_unit
   , ISNULL( CAST(ROUND(oxygen, 3) AS varchar(16)), 'N/A') AS oxygen
   , ISNULL( CAST(PH AS varchar(8)), 'N/A') AS ph
   , ISNULL( CAST(ROUND(turbidity, 1) AS varchar(16)), 'N/A') AS turbidity
   , ISNULL( CAST(ROUND(velocity, 1) AS varchar(16)), 'N/A') AS velocity
   , ( CASE WHEN country = 'US' THEN 'ft/s' ELSE 'm/s' END ) AS velocity_unit
   FROM 
   (
     SELECT mli, state, lat, lon, id, sid, locName, city, country, stamp
          , CAST(stamp AS date) AS dt, CAST(stamp AS time) AS tm
        , CASE WHEN country = 'US' THEN 32 + (temperature / 1.8) ELSE temperature END  AS temperature
        , CASE WHEN country = 'US' THEN discharge * 35.314666721489 ELSE discharge END  AS discharge
        , CASE WHEN country = 'US' THEN elevation * 3.28084 ELSE elevation END  AS elevation
        , PH, oxygen, turbidity
        , CASE WHEN country = 'US' THEN velocity * 35.3147 ELSE velocity END  AS velocity
        FROM dbo.vw_WaterData 
    )z
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vUpdateWaterData' AND type = 'V')
    DROP VIEW dbo.vUpdateWaterData
GO

CREATE view dbo.vUpdateWaterData
WITH SCHEMABINDING
as 
  SELECT TOP 100 MLI, state, updData FROM dbo.WaterStation 
    WHERE updData is not null
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_editor_fish_food' AND type = 'V')
    DROP VIEW dbo.vw_editor_fish_food
GO

CREATE VIEW dbo.vw_editor_fish_food
WITH SCHEMABINDING
AS
  SELECT  fish_id, fish_name, fish_latin
        , food_habitat, terrestrial_insects
        , crustaceans, terrestrial_animals, locked, node_food_habitat, stamp
        , (select userName from dbo.users where id=editor) AS editor 
  FROM dbo.fish
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_fish_image' AND type = 'V')
    DROP VIEW dbo.vw_fish_image
GO

CREATE VIEW [dbo].vw_fish_image
WITH SCHEMABINDING
AS
  SELECT  f.fish_id, fish_image_gender, fish_image_pic, fish_image_id, fish_image_source, fish_image_author, fish_image_link, fish_image_label
        , fish_image_tag, fish_image_stamp, fish_image_location, fish_image_lat, fish_image_lon
  FROM dbo.fish f 
    LEFT JOIN dbo.fish_image z ON z.fish_Id = f.fish_id
GO
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_fish_spot' AND type = 'V')
    DROP VIEW dbo.vw_fish_spot
GO

CREATE VIEW dbo.vw_fish_spot
WITH SCHEMABINDING
AS
     select  spot_lat, spot_lon, b.spot_sid 
        from dbo.Spot a LEFT JOIN dbo.fish_spot b ON a.spot_id = b.spot_id
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_plot_weather' AND type = 'V')
    DROP VIEW dbo.vw_plot_weather
GO

-- Called from FishTracker.Forecast.Plot.LoadPlaceLatLon
-- SELECT * FROM dbo.vw_plot_weather WHERE sid=264119
CREATE VIEW dbo.vw_plot_weather
-- WITH SCHEMABINDING
AS
    SELECT dt,  wind_degree
    , CAST(ISNULL(rain_today, 0.0) AS INT) AS precipitation
    , humidity, wind_direction
    , ISNULL(ROUND(pressure, 1), 0.0) AS pressure
    , CAST(ROUND(tmLow, 1) AS INT) AS temperature_low
    , CAST(ROUND(tmHigh, 1) AS INT) AS temperature_high
    , CAST(ROUND(wind_max_speed, 1) AS INT) AS wind_max_speed
    , shortText, longText, icon, wt.sid as sid
      FROM dbo.weather_Forecast wf 
        JOIN dbo.WaterStation wt on wt.mli = wf.mli
        WHERE dt >= CAST(DATEADD(DAY, -14, getdate()) AS DATE)  
GO
-------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_read_fish_spawn' AND type = 'V')
    DROP VIEW dbo.vw_read_fish_spawn
GO

CREATE VIEW dbo.vw_read_fish_spawn
WITH SCHEMABINDING
AS
  SELECT  f.fish_id, f.fish_name, fish_latin, periodStart, periodEnd, r.habitat, r.spawnsOver
         , tu.ri_min AS tuLD , tu.ri_low AS tuL , tu.ri_avg AS tuC , tu.ri_high AS tuH , tu.ri_max AS tuHD 
         , tm.ri_min AS tmLD , tm.ri_low AS tmL , tm.ri_avg AS tmC , tm.ri_high AS tmH , tm.ri_max AS tmHD 
         , ox.ri_min AS oxLD , ox.ri_low AS oxL , ox.ri_avg AS oxC , ox.ri_high AS oxH , ox.ri_max AS oxHD 
         , ph.ri_min AS phLD , ph.ri_low AS phL , ph.ri_avg AS phC , ph.ri_high AS phH , ph.ri_max AS phHD 
         , ve.ri_min AS veL, ve.ri_max AS veH
         , sa.ri_min AS saL, sa.ri_max AS saH
         , ni.ri_min AS niL, ni.ri_max AS niH
         , phosphat.ri_min AS phosphatL, phosphat.ri_max AS phosphatH
         , depth.ri_min AS fish_spawnDepth_min, depth.ri_max AS fish_spawnDepth_max
         , r.locked, r.stamp
         , (select userName from dbo.users where id=r.editor) AS editor 
  FROM dbo.fish f 
    LEFT JOIN dbo.fish_Rule r ON r.fish_Id = f.fish_id 
    LEFT JOIN dbo.real_interval depth ON depth.ri_parent_id = r.id AND depth.ri_type = 2
    LEFT JOIN dbo.real_interval ph ON ph.ri_parent_id = r.id AND ph.ri_type = 8
    LEFT JOIN dbo.real_interval tm ON tm.ri_parent_id = r.id AND tm.ri_type = 16
    LEFT JOIN dbo.real_interval tu ON tu.ri_parent_id = r.id AND tu.ri_type = 24
    LEFT JOIN dbo.real_interval ox ON ox.ri_parent_id = r.id AND ox.ri_type = 32
    LEFT JOIN dbo.real_interval ve ON ve.ri_parent_id = r.id AND ve.ri_type = 40
    LEFT JOIN dbo.real_interval sa ON sa.ri_parent_id = r.id AND sa.ri_type = 48
    LEFT JOIN dbo.real_interval phosphat ON phosphat.ri_parent_id = r.id AND phosphat.ri_type = 56
    LEFT JOIN dbo.real_interval ni ON ni.ri_parent_id = r.id AND ni.ri_type = 64
  WHERE periodStart <> -1 AND periodEnd <> -1
GO
-------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_read_fish_zoo' AND type = 'V')
    DROP VIEW dbo.vw_read_fish_zoo
GO

--- select * from [dbo].vw_read_fish_zoo order by stamp desc
CREATE VIEW [dbo].vw_read_fish_zoo
WITH SCHEMABINDING
AS
  SELECT  f.fish_id, f.fish_name, f.fish_latin, 1 AS locked, 'Max' AS editor,
          fish_max_length, fish_avg_length, fish_avg_weight, fish_max_weight, natural_color, fish_zoo_image
        , fin, body, Longevity, coloration, Counts, shape, external_morphology, internal_morphology, z.stamp
  FROM dbo.fish f 
    LEFT JOIN dbo.fish_zoo z ON z.fish_Id = f.fish_id
GO
-- select * from [dbo].vw_read_fish_zoo order by stamp desc
------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_regulations' AND type = 'V')
    DROP VIEW dbo.vw_regulations
GO

create VIEW dbo.vw_regulations
WITH SCHEMABINDING
AS
    SELECT l.Lake_id, l.lake_name, r.fish_id, f.fish_name, regulations_part AS part
    , regulations_date_start AS date_start
    , regulations_date_end AS date_end
    , ( 
          CASE WHEN ( regulations_code = 1 OR regulations_code = 3 OR regulations_code = 4 ) AND r.fish_id IS NULL 
            THEN 'Fish sanctuary - no fishing. ' 
            ELSE CASE WHEN ( regulations_code = 1 OR regulations_code = 3 OR regulations_code = 4 ) AND r.fish_id IS NOT NULL THEN (SELECT fish_name FROM dbo.fish f WHERE f.fish_id = r.fish_id ) + ' is closed '
                + CASE WHEN regulations_date_start IS NULL AND regulations_date_end IS NULL THEN ' all the time. ' END
            ELSE '' END
          END
        + CASE WHEN ( regulations_code = 2 OR regulations_code = 3 ) 
            THEN 'Live fish may not be used as bait or possessed for use as bait. '  ELSE '' END
        + CASE WHEN regulations_code = 2 AND r.fish_id IS NOT NULL THEN (SELECT fish_name FROM dbo.fish f WHERE f.fish_id = r.fish_id ) 
          ELSE '' END
        + CASE WHEN ( regulations_code = 8 AND r.fish_id IS NOT NULL ) 
            THEN (SELECT fish_name FROM dbo.fish f WHERE f.fish_id = r.fish_id ) + ' is open ' 
          ELSE '' END
        + CASE WHEN regulations_date_start  IS NOT NULL OR regulations_start IS NOT NULL  THEN ' From ' ELSE '' END 
        + CASE WHEN regulations_date_start  IS NOT NULL THEN datename(month, regulations_date_start) + '/' + datename(day, regulations_date_start) ELSE '' END 
        + CASE WHEN regulations_start       IS NOT NULL THEN regulations_start ELSE '' END 
        + CASE WHEN (regulations_date_start IS NOT NULL OR regulations_start IS NOT NULL) AND (regulations_date_end IS NOT NULL OR regulations_end IS NOT NULL) THEN ' to ' ELSE '' END 
        + CASE WHEN regulations_end         IS NOT NULL THEN regulations_end ELSE '' END 
        + CASE WHEN regulations_date_end    IS NOT NULL THEN datename(month, regulations_date_end) + '/' + datename(day, regulations_date_end) ELSE '' END 
        + ' ' + COALESCE (regulations_text, '') 
       ) AS Value
    , regulations_code AS code, regulations_link AS link, regulations_stamp AS stamp
    FROM dbo.regulations r 
        LEFT JOIN dbo.lake l ON l.lake_id = r.lake_id
        LEFT JOIN dbo.fish f ON f.fish_id = r.fish_id
GO
-- SELECT * FROM vw_regulations order by stamp
-----------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_zone_regulation' AND type = 'V')
    DROP VIEW dbo.vw_zone_regulation
GO

---     SELECT * FROM vw_zone_regulation WHERE zone_id = 2 ORDER BY regulations_stamp DESC;
create VIEW vw_zone_regulation
  WITH SCHEMABINDING
AS 
    SELECT f.fish_name, f.fish_id, zone_id,
        CASE 
            WHEN regulations_code  = 4 THEN 'No close time'
            WHEN regulations_code  = 8 THEN 
                ISNULL(CAST(regulations_date_start AS varchar(16)), regulations_start) + ' to ' + ISNULL(CAST(regulations_date_end AS varchar(16)), regulations_end)
        END AS close_time,
        regulations_sport_text, regulations_consr_text, regulations_code, regulations_link, regulations_stamp,
        regulations_date_start, regulations_date_end
        FROM dbo.zone_regulations z JOIn dbo.fish f ON z.fish_id = f.fish_id
GO
---------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vLastCurrentWaterState' AND type = 'V')
    DROP VIEW dbo.vLastCurrentWaterState
GO

CREATE VIEW dbo.vLastCurrentWaterState
AS 
SELECT mli, stamp, temperature, discharge, turbidity, oxygen, ph, elevation 
  FROM dbo.vCurrentWaterState  
    WITH (NOLOCK) WHERE iterstamp >= DATEADD(hour, -1, GETUTCDATE())
GO    
--select * from vLastCurrentWaterState order by stamp desc
--SELECT * FROM vLastCurrentWaterState
-- SELECT * FROM vCurrentWaterState order by iterstamp desc
GO
-------------------------------------  bool TReading::LoadFromDb(const wchar_t* wzConnStr) --------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vCurrentWaterState' AND type = 'V')
    DROP VIEW dbo.vCurrentWaterState
GO
CREATE VIEW vCurrentWaterState  
WITH SCHEMABINDING
AS
  SELECT mli, stamp, CAST(temperature AS char(16)) as temperature
  , CAST(discharge AS char(16)) as discharge
  , CAST(turbidity AS char(16)) as turbidity
  , CAST(oxygen AS char(16)) as oxygen
  , CAST(ph AS char(16)) as ph
  , CAST(elevation AS char(16)) as elevation 
  , iterstamp
  FROM dbo.CurrentWaterState WITH (NOLOCK)
GO
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_location_trial' AND xtype = 'IF')
    DROP function dbo.fn_map_location_trial
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_location' AND xtype = 'IF')
    DROP function dbo.fn_map_location
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_get_trial_location' AND xtype = 'IF')
    DROP function dbo.fn_get_trial_location
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_location_trial' AND xtype = 'IF')
    DROP function dbo.fn_map_location_trial
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetLocations' AND xtype = 'TF')
    DROP function dbo.GetLocations
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStationInfo' AND xtype = 'TF')
    DROP function dbo.GetStationInfo
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetStation' AND xtype = 'TF')
    DROP function dbo.GetStation
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'GetFisNamePlaceDescr' AND xtype = 'TF')
    DROP function dbo.GetFisNamePlaceDescr
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vStationInfo' AND type = 'V')
    DROP VIEW dbo.vStationInfo
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vWaterStation' AND type = 'V')
    DROP VIEW dbo.vWaterStation
GO
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vWaterStation' AND type = 'V')
    DROP VIEW dbo.vWaterStation
GO

CREATE VIEW dbo.vWaterStation 
WITH SCHEMABINDING
AS
  SELECT id, sid, mli, lat, lon, locType, locName, city, country
       , [state], County, condition, wheatherStamp, lakeId from dbo.WaterStation
GO
/*
-----------------------------------  display selected monitoring station ------------------------------------------
*/
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vStationInfo' AND type = 'V')
    DROP VIEW dbo.vStationInfo
GO

CREATE VIEW dbo.vStationInfo
WITH SCHEMABINDING
AS
  SELECT w.wheatherStamp, w.lat, w.lon, w.condition, county
       , city, [state], locName, w.id, f.today, f.fish_Id
       , s.temperature, s.turbidity, s.oxygen, w.sid, w.mli
       , s.[stamp], s.discharge, s.elevation 
    FROM dbo.vWaterStation w, dbo.CurrentWaterState s, dbo.fish_location f
    WHERE w.mli=s.mli AND f.station_Id=w.id
GO
/*
-----------------------------------  display selected monitoring station ------------------------------------------
*/
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vStationInfo' AND type = 'V')
    DROP VIEW dbo.vStationInfo
GO
-------------------------------------------------------------------------------------------------------
CREATE VIEW dbo.vStationInfo 
WITH SCHEMABINDING
AS
  SELECT w.wheatherStamp, w.lat, w.lon, w.condition, county
       , city, [state], locName, w.id, f.today, f.fish_Id
       , s.temperature, s.turbidity, s.oxygen, w.sid, w.mli
       , s.[stamp], s.discharge, s.elevation 
    FROM dbo.vWaterStation w, dbo.CurrentWaterState s, dbo.fish_location f
    WHERE w.mli=s.mli AND f.station_Id=w.id
GO
-------------------------------------------------------------------------------------------------------
/*
-----------------------------------  display last modifyed lake ------------------------------------------
*/
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vDefaultLastLake' AND type = 'V')
    DROP VIEW dbo.vDefaultLastLake
GO
-- SELECT * FROM dbo.vDefaultLastLake
-- performance sux big time about 6 seconds!!!!!using fn_DefaultLastLake insted of
-- not used
CREATE VIEW dbo.vDefaultLastLake
AS
SELECT lake_id, lake_name, french_name, native, stamp, source_Lat, source_Lon, mouth_Lat, mouth_Lon
     , dbo.fn_CombineLocation( s_district, s_region, s_municipality, s_county, s_city, s_location )      AS source_loc
     , dbo.fn_CombineLocation( m_district, m_region, m_municipality, m_county, m_city, m_location )      AS mouth_loc
FROM
(
SELECT TOP 1 l.lake_id, l.lake_name, l.french_name, l.native, l.stamp
        , s.lat AS source_Lat, s.lon AS source_Lon, m.Lat AS mouth_Lat, m.Lon AS mouth_Lon
        , s.district as s_district, s.region as s_region, s.municipality as s_municipality, s.county as s_county, s.city as s_city, s.location as s_location
        , m.district as m_district, m.region as m_region, m.municipality as m_municipality, m.county as m_county, m.city as m_city, m.location as m_location
        FROM dbo.lake l WITH (INDEX (idx_Lake_stamp)) 
            JOIN dbo.Tributaries m WITH (INDEX (IDX_Tributaries_DEF)) ON m.main_lake_id = l.lake_id AND m.side = 32
            JOIN dbo.Tributaries s WITH (INDEX (IDX_Tributaries_DEF)) ON s.main_lake_id = l.lake_id AND s.side = 16
        WHERE s.Lat IS NOT NULL AND s.Lon IS NOT NULL  
    ORDER BY l.stamp DESC
)x
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vDefaultNews' AND type = 'V')
    DROP VIEW dbo.vDefaultNews
GO
-- SELECT * FROM dbo.vDefaultNews ORDER BY ORD ASC
-- 5270EACB-96B6-41BD-A92C-1E3A5A634CB9
-- Used in default.aspx
CREATE VIEW dbo.vDefaultNews
AS
    WITH cte AS
    (
        SELECT news_id, 1 AS nn FROM (select TOP 2 news_id from news WHERE news_publish = 1 AND country = 'CA' AND news_photo0 IS NOT NULL ORDER BY news_stamp DESC)x
        UNION
        SELECT news_id, 2 AS nn FROM (select TOP 2 news_id from news WHERE news_publish = 1 AND news_photo0 IS NOT NULL ORDER BY stamp DESC)y
    )
    SELECT TOP 5 news.news_id, news.news_title, news.news_author, news.news_author_link, news.news_source, news.news_source_link
    , CASE WHEN ORD = 1 THEN news.news_photo0 ELSE NULL END AS news_photo0
    , news.news_photo_author0, news.news_paragraph0, news.news_photo_alt0
    , CASE WHEN ORD = 1 THEN news.news_photo1 ELSE NULL END AS news_photo1
    , news.news_photo_author1, news.news_paragraph1, news.news_photo_alt1
    , news.news_stamp, news.stamp, news.country, fish1_id, fish2_id, fish3_id
    , news.lake_id, l.lake_name
         , (SELECT fish_name FROM fish WHERE fish_id = fish1_id) AS fish1_name
         , (SELECT fish_name FROM fish WHERE fish_id = fish2_id) AS fish2_name
         , (SELECT fish_name FROM fish WHERE fish_id = fish3_id) AS fish3_name
         , ORD FROM 
    (
        SELECT news_id, MIN(nn) AS ORD FROM 
        (
            SELECT news_id, nn FROM cte
            UNION
            SELECT news_id, nn FROM 
            (
                SELECT TOP 3 news_id, 3 AS nn FROM (select TOP 3 news_id from news WHERE news_publish = 1 AND country = 'CA' ORDER BY news_stamp DESC)x
                    WHERE NOT EXISTS (SELECT news_id FROM cte WHERE cte.news_id = x.news_id)
                UNION
                SELECT TOP 3 news_id, 4 AS nn FROM (select TOP 3 news_id from news WHERE news_publish = 1 AND country = 'US' ORDER BY news_stamp DESC)y
                    WHERE NOT EXISTS (SELECT news_id FROM cte WHERE cte.news_id = y.news_id)
                UNION
                SELECT TOP 3 news_id, 5 AS nn FROM (select TOP 3 news_id from news WHERE news_publish = 1 AND country NOT IN ( 'US', 'CA') ORDER BY news_stamp DESC)z
                    WHERE NOT EXISTS (SELECT news_id FROM cte WHERE cte.news_id = z.news_id)
            )y
        )k GROUP BY news_id
    )u JOIN news ON u.news_id = news.news_id 
	LEFT JOIN lake l ON l.lake_id = news.lake_id
	ORDER BY ORD ASC
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vNewsList' AND type = 'V')
    DROP VIEW dbo.vNewsList
GO
-- select id, news_id, title, source, stamp, flag from vNewsList ORDER BY id DESC
-- Used in default.aspx
CREATE VIEW dbo.vNewsList
AS
    SELECT row_number() over (order by id DESC) AS id, 
	     news.id AS nid, news_id, news_title AS title, news_source AS source
	     , CAST(CAST(news_stamp AS DATE) AS char(10)) AS stamp
	     , country AS flag, x.cnt 
	FROM news
		, (SELECT COUNT(*) AS cnt FROM news WHERE news_publish = 1)x
    WHERE news_publish = 1
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
