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
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spOAuthLoginOrCreateUser' AND type = 'P')
    DROP PROCEDURE dbo.spOAuthLoginOrCreateUser
GO

CREATE PROCEDURE dbo.spOAuthLoginOrCreateUser
      @provider        NVARCHAR(100)
    , @providerUserId  NVARCHAR(256)
    , @email           NVARCHAR(255)
    , @givenName       NVARCHAR(64) = NULL
    , @familyName      NVARCHAR(64) = NULL
    , @ipaddr          VARCHAR(32) = NULL
    , @agent           VARCHAR(128) = NULL
    , @addr            VARCHAR(32) = NULL
    , @host            VARCHAR(255) = NULL
    , @country         CHAR(2) = NULL
    , @postal          VARCHAR(16) = NULL
    , @userId          UNIQUEIDENTIFIER OUTPUT
    , @userName        NVARCHAR(256) OUTPUT
    , @isNewUser       BIT OUTPUT
AS
SET NOCOUNT ON

BEGIN TRY
    SET @userId = NULL;
    SET @userName = NULL;
    SET @isNewUser = 0;

    SET @email          = NULLIF(LTRIM(RTRIM(@email)), N'');
    SET @provider       = NULLIF(LTRIM(RTRIM(@provider)), N'');
    SET @providerUserId = NULLIF(LTRIM(RTRIM(@providerUserId)), N'');

    -- Default the provider to Google when the caller omits it.
    IF @provider IS NULL SET @provider = N'Google';

    -- Every Users row needs a unique email. Providers that do not expose one (e.g. the
    -- Twitter/X OAuth2 API has no email scope) must pass a synthetic address from the
    -- caller (twitter_<id>@users.fishfind.info), so @email is still required here.
    IF @email IS NULL
    BEGIN
        RAISERROR('OAuth login requires an email claim.', 16, 1);
        RETURN;
    END

    IF @providerUserId IS NULL
    BEGIN
        RAISERROR('OAuth login requires a provider user id (sub).', 16, 1);
        RETURN;
    END

    DECLARE @displayName NVARCHAR(256) =
        NULLIF(LTRIM(RTRIM(ISNULL(@givenName, N'') + N' ' + ISNULL(@familyName, N''))), N'');

    --------------------------------------------------------------------------------
    -- 1) Known external login -> return its user, refresh the login row.
    --------------------------------------------------------------------------------
    SELECT TOP 1
          @userId   = u.id
        , @userName = u.userName
    FROM dbo.UserExternalLogin l
    INNER JOIN dbo.Users u ON u.id = l.userId
    WHERE l.provider = @provider
      AND l.providerUserId = @providerUserId;

    IF @userId IS NOT NULL
    BEGIN
        UPDATE dbo.UserExternalLogin
           SET lastLoginUtc = SYSUTCDATETIME()
             , email        = LEFT(@email, 128)
             , displayName  = @displayName
         WHERE provider = @provider
           AND providerUserId = @providerUserId;

        SET @isNewUser = 0;
        RETURN;
    END

    --------------------------------------------------------------------------------
    -- 2) No external login yet: link to an existing user with the same email,
    --    otherwise create a brand-new user.
    --------------------------------------------------------------------------------
    SELECT TOP 1
          @userId   = id
        , @userName = userName
    FROM dbo.Users
    WHERE email = @email;

    IF @userId IS NULL
    BEGIN
        SET @userId = NEWID();

        -- For providers whose email is synthetic (Twitter/X), show the provider display
        -- name (the @handle / real name) as the userName instead of the fake address.
        -- Google keeps using the email, exactly as before.
        IF @provider <> N'Google' AND DATALENGTH(@displayName) >= 3
            SET @userName = LEFT(@displayName, 64);
        ELSE
            SET @userName = @email;

        INSERT INTO dbo.Users
        (
              ID
            , userName
            , email
            , ipaddr
            , agent
            , addr
            , host
            , country
            , postal
            , firstName
            , lastName
            , psw
            , question
            , answer
            , authType
        )
        VALUES
        (
              @userId
            , @userName
            , @email
            , ISNULL(@ipaddr, '')
            , ISNULL(@agent, '')
            , ISNULL(@addr, '')
            , ISNULL(@host, '')
            , ISNULL(@country, 'CA')
            , ISNULL(@postal, '')
            , ISNULL(@givenName, '')
            , ISNULL(@familyName, '')
            , HASHBYTES('MD5', CONVERT(VARCHAR(36), NEWID()) + '*oauth')
            , 'oauth'
            , 0x0024
            , 'OAuth'
        );

        SET @isNewUser = 1;
    END

    -- Link the external login to the (new or existing) user.
    INSERT INTO dbo.UserExternalLogin
        ( userId, provider, providerUserId, email, displayName, lastLoginUtc )
    VALUES
        ( @userId, @provider, @providerUserId, LEFT(@email, 128), @displayName, SYSUTCDATETIME() );
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
GO 
-------------------------------------------------------------------------------------------------------
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
	  INSERT INTO SessionHandler(  ip4,  userAgent,  host,  startPage ) 
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
-- 1. update fish probability based on catch probability - used in spTotalUpdateProbability
-- use fish_catch_probability to update probabilites in fish_location based on by month fish's activity 
-- by default we asume probability is 100% since it was registred in documents
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spTotalUpdateCatch' AND xtype = 'P')
    DROP PROCEDURE dbo.spTotalUpdateCatch
GO
----------------------------------------------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[spTotalUpdateCatch]
WITH EXEC AS CALLER
AS
SET NOCOUNT ON
BEGIN TRY  
    DECLARE @return_value int = 0;

    ;WITH cte (today, station_Id, fish_Id) AS
    (
        SELECT
            ISNULL(fcp.probability, t.probability),
            t.station_Id,
            t.fish_Id
        FROM dbo.fish_location t
        INNER JOIN dbo.fish_catch_probability fcp
            ON t.fish_Id = fcp.fish_id
            AND fcp.month = DATEPART(MONTH, GETUTCDATE())
    )
    UPDATE t
        SET t.stamp = GETUTCDATE(),
            t.today = cte.today
    FROM dbo.fish_location t
    JOIN cte
        ON t.station_Id = cte.station_Id
        AND t.fish_Id = cte.fish_Id
    WHERE t.probability <> cte.today;

    SET @return_value = @@ROWCOUNT;
        
    RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spTotalUpdateLunar' AND xtype = 'P')
    DROP PROCEDURE dbo.spTotalUpdateLunar
GO
----------------------------------------------------------------------------------------------------------------------------
-- 2. Combined Probability Update (Monthly × Lunar) - must be called after 1. [spTotalUpdateCatch]
-- whatever day of the month it is today, pull that row's probability and use it as the multiplier. Everything else stays the same.
-- if probability over 100% on next step count it as 100%
----------------------------------------------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[spTotalUpdateLunar]
WITH EXEC AS CALLER
AS
SET NOCOUNT ON
BEGIN TRY  
    DECLARE @return_value int = 0;

    UPDATE t
        SET t.today = ROUND(
                t.today * (lp.probability / 100.0)
            , 0),
            t.stamp = GETUTCDATE()
    FROM dbo.fish_location t
    INNER JOIN dbo.fish_lunar_catch_probability lp
        ON lp.fish_id = t.fish_Id
        AND lp.day    = DATEPART(DAY, GETUTCDATE())
    WHERE t.today <> ROUND(t.today * (lp.probability / 100.0), 0);

    SET @return_value = @@ROWCOUNT;
        
    RETURN @return_value;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;   
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drop existing procedure if it exists
IF OBJECT_ID('dbo.sp_upsert_fish_temperature_probability', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_upsert_fish_temperature_probability;
GO

-- 3. update fish probability based on water temperature
-- if fish not in most comfort  temperature zone drop probaility 33% and 5% if out of middle zone
-- Update fish probability based on water temperature with bell curve (can only decrease)
CREATE PROCEDURE dbo.sp_upsert_fish_temperature_probability
AS
SET NOCOUNT ON;
BEGIN TRY
    ;WITH fish_temp_habitat AS
    (
        SELECT f.fish_id, ri.ri_min AS tmL, ri.ri_low AS tmL90, ri.ri_avg AS tmOptimal, ri.ri_high AS tmH90, ri.ri_max AS tmH
        FROM dbo.fish f
        INNER JOIN dbo.fish_Rule r ON r.fish_Id = f.fish_id
        INNER JOIN dbo.real_interval ri ON ri.ri_parent_id = r.id AND ri.ri_type = 17
        WHERE r.periodStart = -1 AND r.periodEnd = -1
    ),
    temperature_coefficients AS
    (
        SELECT
            fl.station_Id,
            fl.fish_Id,
            CAST(
                CASE
                    WHEN cws.temperature < fth.tmL OR cws.temperature > fth.tmH THEN 0.00
                    WHEN cws.temperature >= fth.tmL AND cws.temperature < ISNULL(fth.tmL90, fth.tmOptimal) THEN
                        0.80 + (0.10 * (CAST(cws.temperature AS FLOAT) - fth.tmL) / NULLIF(ISNULL(fth.tmL90, fth.tmOptimal) - fth.tmL, 0))
                    WHEN cws.temperature >= ISNULL(fth.tmL90, fth.tmOptimal) AND cws.temperature < fth.tmOptimal THEN
                        0.90 + (0.10 * (CAST(cws.temperature AS FLOAT) - ISNULL(fth.tmL90, fth.tmOptimal)) / NULLIF(fth.tmOptimal - ISNULL(fth.tmL90, fth.tmOptimal), 0))
                    WHEN cws.temperature = fth.tmOptimal THEN 1.00
                    WHEN cws.temperature > fth.tmOptimal AND cws.temperature <= ISNULL(fth.tmH90, fth.tmOptimal) THEN
                        1.00 - (0.10 * (CAST(cws.temperature AS FLOAT) - fth.tmOptimal) / NULLIF(ISNULL(fth.tmH90, fth.tmOptimal) - fth.tmOptimal, 0))
                    WHEN cws.temperature > ISNULL(fth.tmH90, fth.tmOptimal) AND cws.temperature <= fth.tmH THEN
                        0.90 - (0.10 * (CAST(cws.temperature AS FLOAT) - ISNULL(fth.tmH90, fth.tmOptimal)) / NULLIF(fth.tmH - ISNULL(fth.tmH90, fth.tmOptimal), 0))
                    ELSE 1.00
                END AS DECIMAL(5,2)
            ) AS koef
        FROM dbo.fish_location fl
        INNER JOIN dbo.WaterStation ws ON ws.id = fl.station_Id
        INNER JOIN dbo.CurrentWaterState cws ON cws.mli = ws.mli
        INNER JOIN fish_temp_habitat fth ON fth.fish_id = fl.fish_Id
        WHERE cws.temperature IS NOT NULL
          AND fth.tmL IS NOT NULL AND fth.tmH IS NOT NULL
    )
    UPDATE fl
    SET 
        fl.stamp = GETUTCDATE(),
        fl.today = CAST(ROUND(fl.today * tc.koef, 0) AS INT)
    FROM dbo.fish_location fl
    INNER JOIN temperature_coefficients tc ON fl.station_Id = tc.station_Id AND fl.fish_Id = tc.fish_Id
    WHERE tc.koef < 1.00;
END TRY
BEGIN CATCH
    THROW;
END CATCH;
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drop existing procedure if it exists
IF OBJECT_ID('dbo.sp_upsert_fish_oxygen_probability', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_upsert_fish_oxygen_probability;
GO

-- 3. update fish probability based on oxygen in water
-- if fish not in most comfort  dissolved oxygen zone drop probaility 33% and 5% if out of middle zone
-- Calculate oxygen coefficients with bell curve: 80% -> 90% -> 100% -> 90% -> 80%
-- Update fish probability based on dissolved oxygen with bell curve (can only decrease)
-- This design ensures safe, conditional updates - only applying oxygen adjustments 
--    where both the environmental data exists AND the fish's oxygen tolerance is known.
CREATE PROCEDURE dbo.sp_upsert_fish_oxygen_probability
AS
SET NOCOUNT ON;
BEGIN TRY
    ;WITH fish_oxygen_habitat AS
    (
        SELECT f.fish_id, ri.ri_min AS oxL, ri.ri_low AS oxL90, ri.ri_avg AS oxOptimal, ri.ri_high AS oxH90, ri.ri_max AS oxH
        FROM dbo.fish f
        INNER JOIN dbo.fish_Rule r ON r.fish_Id = f.fish_id
        INNER JOIN dbo.real_interval ri ON ri.ri_parent_id = r.id AND ri.ri_type = 33
        WHERE r.periodStart = -1 AND r.periodEnd = -1
    ),
    oxygen_coefficients AS
    (
        SELECT
            fl.station_Id,
            fl.fish_Id,
            CAST(
                CASE
                    WHEN cws.oxygen < foh.oxL OR cws.oxygen > foh.oxH THEN 0.00
                    WHEN cws.oxygen >= foh.oxL AND cws.oxygen < ISNULL(foh.oxL90, foh.oxOptimal) THEN
                        0.80 + (0.10 * (CAST(cws.oxygen AS FLOAT) - foh.oxL) / NULLIF(ISNULL(foh.oxL90, foh.oxOptimal) - foh.oxL, 0))
                    WHEN cws.oxygen >= ISNULL(foh.oxL90, foh.oxOptimal) AND cws.oxygen < foh.oxOptimal THEN
                        0.90 + (0.10 * (CAST(cws.oxygen AS FLOAT) - ISNULL(foh.oxL90, foh.oxOptimal)) / NULLIF(foh.oxOptimal - ISNULL(foh.oxL90, foh.oxOptimal), 0))
                    WHEN cws.oxygen = foh.oxOptimal THEN 1.00
                    WHEN cws.oxygen > foh.oxOptimal AND cws.oxygen <= ISNULL(foh.oxH90, foh.oxOptimal) THEN
                        1.00 - (0.10 * (CAST(cws.oxygen AS FLOAT) - foh.oxOptimal) / NULLIF(ISNULL(foh.oxH90, foh.oxOptimal) - foh.oxOptimal, 0))
                    WHEN cws.oxygen > ISNULL(foh.oxH90, foh.oxOptimal) AND cws.oxygen <= foh.oxH THEN
                        0.90 - (0.10 * (CAST(cws.oxygen AS FLOAT) - ISNULL(foh.oxH90, foh.oxOptimal)) / NULLIF(foh.oxH - ISNULL(foh.oxH90, foh.oxOptimal), 0))
                    ELSE 1.00
                END AS DECIMAL(5,2)
            ) AS koef
        FROM dbo.fish_location fl
        INNER JOIN dbo.WaterStation ws ON ws.id = fl.station_Id
        INNER JOIN dbo.CurrentWaterState cws ON cws.mli = ws.mli
        INNER JOIN fish_oxygen_habitat foh ON foh.fish_id = fl.fish_Id
        WHERE cws.oxygen IS NOT NULL
          AND foh.oxL IS NOT NULL AND foh.oxH IS NOT NULL
    )
    UPDATE fl
    SET 
        fl.stamp = GETUTCDATE(),
        fl.today = CAST(ROUND(fl.today * oc.koef, 0) AS INT)
    FROM dbo.fish_location fl
    INNER JOIN oxygen_coefficients oc ON fl.station_Id = oc.station_Id AND fl.fish_Id = oc.fish_Id
    WHERE oc.koef < 1.00;
END TRY
BEGIN CATCH
    THROW;
END CATCH;
GO
----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'spTotalUpdateProbability' AND xtype = 'P')
    DROP PROCEDURE dbo.spTotalUpdateProbability
GO

-- EXEC spTotalUpdateProbability
----------------------------------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.spTotalUpdateProbability
WITH EXEC AS CALLER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @return_value int = 0;

    BEGIN TRY
        BEGIN TRANSACTION;
        -- 1. reset probability to unknown state for week old probabilites
        UPDATE fish_location SET today = 100 WHERE stamp < DATEADD(DAY, -7, GETUTCDATE())  
        UPDATE [CurrentWaterState] SET temperature = NULL, oxygen = NULL
            WHERE stamp < DATEADD(DAY, -7, GETUTCDATE())  


        -- 2. update fish probability based on catch probability
        EXEC dbo.spTotalUpdateCatch

        -- 3. update fish probability based on lunar
        EXEC dbo.spTotalUpdateLunar

        -- update fish probability based on water temperature
        EXEC dbo.sp_upsert_fish_temperature_probability


        -- update fish probability based on oxygen
        EXEC dbo.sp_upsert_fish_oxygen_probability

        SET @return_value = @return_value + @@ROWCOUNT;

        COMMIT TRANSACTION;

        RETURN @return_value;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END              
GO
----------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------
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

create PROCEDURE sp_update_fish_general @fish_id uniqueidentifier, @locked bit, @editor uniqueidentifier, @fish_description nvarchar(2048), @fish_uses nvarchar(2048)
AS
SET NOCOUNT ON
BEGIN TRY  
    UPDATE dbo.fish Set stamp = GETUTCDATE(), locked = @locked, editor=@editor, descrip = @fish_description, uses = @fish_uses
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
            EXEC sp_add_fish_image 'f83d9508-bf50-41b8-b22c-7accbb6713dd', 0xFF, N'fish_zoo', N'fish_zoo_image', 1, N'source', N'author', N'www.ca', N'label', N'location', 40, -80, N'tag', '2026-01-01'
 */
/*
 select * from fish_image 
 delete from fish_image where fish_id = 'C2E8C307-F470-458B-8CEE-000999277126'
 update fish_zoo set [fish_zoo_image] = null
*/
CREATE PROCEDURE [dbo].[sp_add_fish_image]
    @fish_id   uniqueidentifier, @image varbinary(max), @tablename sysname, @colname sysname,
    @gender bit, @source nvarchar(255), @author nvarchar(255), @link nvarchar(255), @label nvarchar(255),
    @location nvarchar(255), @lat float, @lon float, @tag nvarchar(255), @stamp nvarchar(255)
AS
SET NOCOUNT ON
BEGIN TRY
    DECLARE @execsql nvarchar(500);
    DECLARE @imageId  int;
    DECLARE @newHash  varbinary(256);

    IF @fish_id IS NOT NULL
    BEGIN
        SET @newHash = HASHBYTES('SHA1', @image);

        -- reuse existing row if same image content
        SELECT @imageId = fish_image_id FROM dbo.fish_image WHERE fish_image_hash = @newHash;

        IF @imageId IS NULL
        BEGIN
            INSERT INTO dbo.fish_image
                ( fish_id, fish_image_pic, fish_image_gender, fish_image_source, fish_image_author,
                  fish_image_link, fish_image_label, fish_image_location, fish_image_lat, fish_image_lon,
                  fish_image_tag, fish_image_stamp, fish_image_hash )
            VALUES
                ( @fish_id, @image, @gender, @source, @author,
                  @link, @label, @location, @lat, @lon,
                  @tag, @stamp, @newHash );
            SET @imageId = SCOPE_IDENTITY();
        END

        IF @imageId IS NOT NULL
           AND EXISTS (SELECT * FROM sys.tables  WHERE name = @tablename)
           AND EXISTS (SELECT * FROM sys.columns WHERE name = @colname)
        BEGIN
            SET @execsql = N'UPDATE ' + @tablename + N' SET ' + @colname
                         + N' = ' + CAST(@imageId AS nvarchar(20))
                         + N' WHERE fish_id = ''' + CAST(@fish_id AS nvarchar(36)) + N'''';
            EXEC (@execsql);
        END
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity,
           ERROR_STATE() AS ErrorState, ERROR_PROCEDURE() AS ErrorProcedure,
           ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
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
    DECLARE @rowcnt int = 0
    IF NOT EXISTS (SELECT * FROM dbo.fish_zoo WHERE fish_Id = @fish_Id)
    BEGIN
        INSERT INTO dbo.fish_zoo( fish_id, fish_max_length, fish_avg_length, fish_max_weight, fish_avg_weight
            , natural_color, longevity, fin, body, counts, shape, external_morphology, internal_morphology  )
         VALUES (@fish_Id, @max_length, @avg_length, @max_weight, @avg_weight, @natural_color, @longevity, @fin, @body, @counts, @shape, @em, @im );
        SET @rowcnt = @@ROWCOUNT
    END
    ELSE
    BEGIN
        UPDATE dbo.fish_zoo SET fish_max_length=@max_length, fish_avg_length=@avg_length, fish_max_weight=@max_weight, fish_avg_weight=@avg_weight
          , natural_color = @natural_color, longevity = @longevity, fin = @fin
           , body = @body, counts = @counts, shape = @shape, external_morphology = @em, internal_morphology = @im 
          WHERE fish_Id = @fish_Id
        SET @rowcnt = @@ROWCOUNT
    END
    IF @rowcnt > 1
        UPDATE dbo.fish Set stamp = GETUTCDATE() WHERE fish_id =  @fish_Id;
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
    Procedure parse TWC (Weather Channel) JSON and upsert into weather_Forecast.
    One row per day (max 6).  Latest daypart values win (night over day).
    MERGE upserts on mli + dt.
    Temperatures converted from °F to °C.
 
        called from [TR_ows_meteo]
*/
CREATE  PROCEDURE [dbo].[sp_ows_meteo]
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
        ---------- daily-level arrays ------------------
        daily_time AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(datetime2(0), REPLACE(LEFT([value], 19), 'T', ' ')) AS validTimeLocal
            FROM OPENJSON(@js, '$.validTimeLocal')
        ),
        daily_tmax AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS tmHigh
            FROM OPENJSON(@js, '$.temperatureMax')
        ),
        daily_tmin AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS tmLow
            FROM OPENJSON(@js, '$.temperatureMin')
        ),
        daily_qpf AS
        (
            SELECT CAST([key] AS int) AS idx, ISNULL(TRY_CONVERT(float, [value]), 0.0) AS qpf
            FROM OPENJSON(@js, '$.qpf')
        ),
        daily_narrative AS
        (
            SELECT CAST([key] AS int) AS idx, [value] AS narrative
            FROM OPENJSON(@js, '$.narrative')
        ),
        daily_data AS
        (
            SELECT
                  t.idx
                , t.validTimeLocal
                , CAST(t.validTimeLocal AS date) AS dt
                , mx.tmHigh
                , mn.tmLow
                , q.qpf
                , n.narrative
            FROM daily_time t
            LEFT JOIN daily_tmax      mx ON mx.idx = t.idx
            LEFT JOIN daily_tmin      mn ON mn.idx = t.idx
            LEFT JOIN daily_qpf       q  ON q.idx  = t.idx
            LEFT JOIN daily_narrative  n  ON n.idx  = t.idx
            WHERE t.validTimeLocal IS NOT NULL
        ),
 
        /* ── daypart arrays (day/night pairs: idx/2 = daily row) */
        dp_dayOrNight AS
        (
            SELECT CAST([key] AS int) AS idx, [value] AS dayOrNight
            FROM OPENJSON(@js, '$.daypart[0].dayOrNight')
        ),
        dp_temperature AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS air_temperature
            FROM OPENJSON(@js, '$.daypart[0].temperature')
        ),
        dp_humidity AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS humidity
            FROM OPENJSON(@js, '$.daypart[0].relativeHumidity')
        ),
        dp_pop AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS pop
            FROM OPENJSON(@js, '$.daypart[0].precipChance')
        ),
        dp_wind_speed AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS wind_max_speed
            FROM OPENJSON(@js, '$.daypart[0].windSpeed')
        ),
        dp_wind_degree AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS wind_degree
            FROM OPENJSON(@js, '$.daypart[0].windDirection')
        ),
        dp_wind_dir AS
        (
            SELECT CAST([key] AS int) AS idx, LEFT([value], 3) AS wind_direction
            FROM OPENJSON(@js, '$.daypart[0].windDirectionCardinal')
        ),
        dp_iconCode AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS iconCode
            FROM OPENJSON(@js, '$.daypart[0].iconCode')
        ),
        dp_wxShort AS
        (
            SELECT CAST([key] AS int) AS idx, [value] AS wxPhraseShort
            FROM OPENJSON(@js, '$.daypart[0].wxPhraseShort')
        ),
        dp_wxLong AS
        (
            SELECT CAST([key] AS int) AS idx, [value] AS wxPhraseLong
            FROM OPENJSON(@js, '$.daypart[0].wxPhraseLong')
        ),
        dp_qpf AS
        (
            SELECT CAST([key] AS int) AS idx, ISNULL(TRY_CONVERT(float, [value]), 0.0) AS dp_qpf
            FROM OPENJSON(@js, '$.daypart[0].qpf')
        ),
        dp_narrative AS
        (
            SELECT CAST([key] AS int) AS idx, [value] AS dp_narrative
            FROM OPENJSON(@js, '$.daypart[0].narrative')
        ),
 
        -----------combine all daypart fields, map to daily index --------------
        daypart_data AS
        (
            SELECT
                  dn.idx
                , dn.idx / 2                AS daily_idx
                , dn.dayOrNight
                , tmp.air_temperature
                , hum.humidity
                , pp.pop
                , ws.wind_max_speed
                , wd.wind_degree
                , wdir.wind_direction
                , ic.iconCode
                , wxs.wxPhraseShort
                , wxl.wxPhraseLong
                , dq.dp_qpf
                , dpn.dp_narrative
            FROM dp_dayOrNight dn
            LEFT JOIN dp_temperature  tmp  ON tmp.idx  = dn.idx
            LEFT JOIN dp_humidity     hum  ON hum.idx  = dn.idx
            LEFT JOIN dp_pop          pp   ON pp.idx   = dn.idx
            LEFT JOIN dp_wind_speed   ws   ON ws.idx   = dn.idx
            LEFT JOIN dp_wind_degree  wd   ON wd.idx   = dn.idx
            LEFT JOIN dp_wind_dir     wdir ON wdir.idx = dn.idx
            LEFT JOIN dp_iconCode     ic   ON ic.idx   = dn.idx
            LEFT JOIN dp_wxShort      wxs  ON wxs.idx  = dn.idx
            LEFT JOIN dp_wxLong       wxl  ON wxl.idx  = dn.idx
            LEFT JOIN dp_qpf          dq   ON dq.idx   = dn.idx
            LEFT JOIN dp_narrative    dpn  ON dpn.idx  = dn.idx
            WHERE dn.dayOrNight IS NOT NULL          -- skip JSON nulls
        ),
 
        ------------------ latest daypart per day (night > day by idx) ------------
        dp_ranked AS
        (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY daily_idx ORDER BY idx DESC) AS rn
            FROM daypart_data
        ),
        latest_dp AS
        (
            SELECT * FROM dp_ranked WHERE rn = 1
        ),
 
        ------------ day/night precipitation split --------------------------
        dp_precip AS
        (
            SELECT
                  daily_idx
                , SUM(CASE WHEN dayOrNight = 'D' THEN dp_qpf ELSE 0 END) AS gpfDay
                , SUM(CASE WHEN dayOrNight = 'N' THEN dp_qpf ELSE 0 END) AS gpfNight
            FROM daypart_data
            GROUP BY daily_idx
        ),
 
        ------------- daytime temperature (D part only) for tmDay -----------
        dp_day_temp AS
        (
            SELECT daily_idx, air_temperature AS tmDay
            FROM daypart_data
            WHERE dayOrNight = 'D'
        ),
 
        ------------- final source: 1 row per day ----------------------------
        src AS
        (
            SELECT
                  @link AS [link]
                /* F → C;  COALESCE mirrors original fallback logic */
                , ROUND((COALESCE(d.tmHigh, lp.air_temperature, d.tmLow) - 32.0) * (5.0/9.0), 1) AS tmHigh
                , ROUND((COALESCE(d.tmLow,  lp.air_temperature, d.tmHigh) - 32.0) * (5.0/9.0), 1) AS tmLow
                , ISNULL(pr.gpfDay, 0.0)   AS gpfDay
                , ISNULL(pr.gpfNight, 0.0)  AS gpfNight
                , lp.humidity
                , lp.wind_max_speed
                , lp.wind_degree
                , lp.wind_direction
                , LEFT(COALESCE(lp.wxPhraseShort, d.narrative), 64)              AS shortText
                , LEFT(COALESCE(lp.wxPhraseLong, lp.dp_narrative, d.narrative), 255) AS longText
                , CONCAT('wc_', ISNULL(CONVERT(varchar(12), lp.iconCode), 'na'), '.png') AS icon
                , lp.pop
                , d.dt
                , CAST(d.validTimeLocal AS time(7)) AS tm
                , @mli AS mli
                , CAST(NULL AS int) AS city_id
                , CAST(NULL AS int) AS pressure           -- not in TWC JSON
                , TRY_CONVERT(int, ROUND(d.qpf, 0))      AS rain_today
                , TRY_CONVERT(int, ROUND((lp.air_temperature - 32.0) * (5.0/9.0), 0)) AS air_temperature
                , ROUND((dt_temp.tmDay - 32.0) * (5.0/9.0), 1) AS tmDay
                , lp.iconCode AS weather_code
            FROM daily_data d
            LEFT JOIN latest_dp   lp      ON lp.daily_idx      = d.idx
            LEFT JOIN dp_precip   pr      ON pr.daily_idx      = d.idx
            LEFT JOIN dp_day_temp dt_temp ON dt_temp.daily_idx  = d.idx
        )
 
        MERGE dbo.weather_Forecast AS t
        USING src
           ON t.mli = src.mli
          AND t.dt  = src.dt
 
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
                , t.shortText         = src.shortText
                , t.longText          = src.longText
                , t.icon              = src.icon
                , t.pop               = src.pop
                , t.tm                = src.tm
                , t.pressure          = src.pressure
                , t.rain_today        = src.rain_today
                , t.air_temperature   = src.air_temperature
                , t.tmDay             = src.tmDay
                , t.weather_code      = src.weather_code
 
        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                  [link], [tmHigh], [tmLow], [gpfDay], [gpfNight]
                , [humidity], [wind_max_speed], [wind_degree], [wind_direction]
                , [shortText], [longText], [icon], [pop]
                , [dt], [tm], [mli], [city_id]
                , [pressure], [rain_today], [air_temperature], [tmDay], [weather_code]
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
                , src.shortText
                , src.longText
                , src.icon
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
        -- ------------------- hourly arrays ----------------------
        hourly_time AS
        (
            SELECT
                  CAST([key] AS int) AS idx
                , TRY_CONVERT(datetime2(0), REPLACE([value], 'T', ' ')) AS validTimeLocal
            FROM OPENJSON(@js, '$.hourly.time')
        ),
        hourly_temperature AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS air_temperature
            FROM OPENJSON(@js, '$.hourly.temperature_2m')
        ),
        hourly_humidity AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS humidity
            FROM OPENJSON(@js, '$.hourly.relative_humidity_2m')
        ),
        hourly_pop AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS pop
            FROM OPENJSON(@js, '$.hourly.precipitation_probability')
        ),
        hourly_pressure AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS pressure
            FROM OPENJSON(@js, '$.hourly.pressure_msl')
        ),
        hourly_wind_speed AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS wind_max_speed
            FROM OPENJSON(@js, '$.hourly.wind_speed_10m')
        ),
        hourly_wind_degree AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS wind_degree
            FROM OPENJSON(@js, '$.hourly.wind_direction_10m')
        ),
        hourly_weather_code AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(int, [value]) AS weather_code
            FROM OPENJSON(@js, '$.hourly.weather_code')
        ),
        hourly_rain AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS rain_mm
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

        ------------------ pick latest hour per day ─────────----------
        hourly_ranked AS
        (
            SELECT *
                 , ROW_NUMBER() OVER (PARTITION BY dt ORDER BY validTimeLocal DESC) AS rn
            FROM hourly_data
        ),
        latest_hourly AS
        (
            SELECT * FROM hourly_ranked WHERE rn = 1
        ),

        ------------------- daily arrays ───────────────────----------
        daily_time AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(date, [value]) AS dt
            FROM OPENJSON(@js, '$.daily.time')
        ),
        daily_tmax AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS tmHigh
            FROM OPENJSON(@js, '$.daily.temperature_2m_max')
        ),
        daily_tmin AS
        (
            SELECT CAST([key] AS int) AS idx, TRY_CONVERT(float, [value]) AS tmLow
            FROM OPENJSON(@js, '$.daily.temperature_2m_min')
        ),
        daily_data AS
        (
            SELECT d.dt, mx.tmHigh, mn.tmLow
            FROM daily_time d
            LEFT JOIN daily_tmax mx ON mx.idx = d.idx
            LEFT JOIN daily_tmin mn ON mn.idx = d.idx
            WHERE d.dt IS NOT NULL
        ),

       ---- rain / daytime temp aggregated per day ─────------------
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

        ---------------- final source: 1 row per day (max 7) ──────------------
        src AS
        (
            SELECT
                  @link AS [link]
                , d.tmHigh
                , d.tmLow
                , ISNULL(r.gpfDay, 0.0)   AS gpfDay
                , ISNULL(r.gpfNight, 0.0)  AS gpfNight
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
            FROM latest_hourly h
            LEFT JOIN daily_data  d ON d.dt = h.dt
            LEFT JOIN rain_by_day r ON r.dt = h.dt
        )

        MERGE dbo.weather_Forecast AS t
        USING src
           ON t.mli = src.mli
          AND t.dt  = src.dt

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
                , t.tm                = src.tm
                , t.pressure          = src.pressure
                , t.rain_today        = src.rain_today
                , t.air_temperature   = src.air_temperature
                , t.tmDay             = src.tmDay
                , t.weather_code      = src.weather_code

        WHEN NOT MATCHED BY TARGET THEN
            INSERT
            (
                  [link], [tmHigh], [tmLow], [gpfDay], [gpfNight]
                , [humidity], [wind_max_speed], [wind_degree], [wind_direction]
                , [shortText], [longText], [icon], [pop]
                , [dt], [tm], [mli], [city_id]
                , [pressure], [rain_today], [air_temperature], [tmDay], [weather_code]
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
--------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_UpdateWaterData' AND type = 'P')
    DROP PROCEDURE dbo.sp_UpdateWaterData
GO

CREATE PROCEDURE dbo.sp_UpdateWaterData
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

            -- Delete records older than 15 days after a successful insert
            DELETE FROM dbo.WaterData
            WHERE @mli = mli AND stamp < DATEADD(DAY, -15, GETDATE());
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
END
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spCleanWeatherWaterData' AND type = 'P')
    DROP PROCEDURE dbo.spCleanWeatherWaterData
GO

CREATE PROCEDURE [dbo].[spCleanWeatherWaterData]  
AS
SET NOCOUNT ON
	BEGIN TRY 
	 delete from [dbo].[WaterData] where stamp < CAST(DATEADD(day, -15, GETDATE()) AS DATE);
	 SELECT @@ROWCOUNT 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;          
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drop existing procedure if it exists
IF OBJECT_ID('dbo.sp_upsert_fish_catch_probability', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_upsert_fish_catch_probability;
GO
/*
-- Example: Set catch probabilities for Salmon, Chinook
EXEC dbo.sp_upsert_fish_catch_probability 
    @fish_id = '5d069a33-6b36-4314-bd49-8a32a6c92245',
    @probability_jan = 5,
    @probability_feb = 5,
    @probability_mar = 10,
    @probability_apr = 30,
    @probability_may = 100,
    @probability_jun = 220,
    @probability_jul = 380,
    @probability_aug = 500,
    @probability_sep = 480,
    @probability_oct = 260,
    @probability_nov = 80,
    @probability_dec = 10;
*/

/*  stored procedure that accepts a fish ID and 12 probability values for storing the catch probability for each month. 
The procedure will validate the input, then use a MERGE statement to insert or update the probabilities 
in the fish_catch_probability table. It will return the number of rows affected.
*/
CREATE PROCEDURE dbo.sp_upsert_fish_catch_probability
(
    @fish_id            uniqueidentifier,
    @probability_jan    smallint,
    @probability_feb    smallint,
    @probability_mar    smallint,
    @probability_apr    smallint,
    @probability_may    smallint,
    @probability_jun    smallint,
    @probability_jul    smallint,
    @probability_aug    smallint,
    @probability_sep    smallint,
    @probability_oct    smallint,
    @probability_nov    smallint,
    @probability_dec    smallint
)
AS
SET NOCOUNT ON
	BEGIN TRY 
 -- Validate fish_id exists
    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @fish_id)
    BEGIN
        RAISERROR('Fish ID does not exist in fish table', 16, 1);
        RETURN;
    END

    -- Validate all probabilities are in valid range (0-500)
    IF (@probability_jan NOT BETWEEN 0 AND 500 OR
        @probability_feb NOT BETWEEN 0 AND 500 OR
        @probability_mar NOT BETWEEN 0 AND 500 OR
        @probability_apr NOT BETWEEN 0 AND 500 OR
        @probability_may NOT BETWEEN 0 AND 500 OR
        @probability_jun NOT BETWEEN 0 AND 500 OR
        @probability_jul NOT BETWEEN 0 AND 500 OR
        @probability_aug NOT BETWEEN 0 AND 500 OR
        @probability_sep NOT BETWEEN 0 AND 500 OR
        @probability_oct NOT BETWEEN 0 AND 500 OR
        @probability_nov NOT BETWEEN 0 AND 500 OR
        @probability_dec NOT BETWEEN 0 AND 500)
    BEGIN
        RAISERROR('All probability values must be between 0 and 500', 16, 1);
        RETURN;
    END

    -- Create a table variable with all 12 months
    DECLARE @MonthData TABLE (month tinyint, probability smallint);
    
    INSERT INTO @MonthData (month, probability)
    VALUES 
        (1,  @probability_jan),
        (2,  @probability_feb),
        (3,  @probability_mar),
        (4,  @probability_apr),
        (5,  @probability_may),
        (6,  @probability_jun),
        (7,  @probability_jul),
        (8,  @probability_aug),
        (9,  @probability_sep),
        (10, @probability_oct),
        (11, @probability_nov),
        (12, @probability_dec);

    -- Use MERGE to insert or update all 12 months
    MERGE INTO dbo.fish_catch_probability AS target
    USING @MonthData AS source
    ON target.fish_id = @fish_id AND target.month = source.month
    WHEN MATCHED THEN
        UPDATE SET target.probability = source.probability
    WHEN NOT MATCHED THEN
        INSERT (fish_id, month, probability)
        VALUES (@fish_id, source.month, source.probability);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;          
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Step 1: Create a User-Defined Table Type
IF TYPE_ID('dbo.DailyProbabilityType') IS NOT NULL
    DROP TYPE dbo.DailyProbabilityType;
GO

/*
-- Declare and populate the table variable
DECLARE @probs dbo.DailyProbabilityType;

INSERT INTO @probs ([day], probability)
VALUES 
    (1, 30), (2, 35), (3, 40), (4, 45), (5, 50), (6, 55), (7, 60),
    (8, 65), (9, 70), (10, 75), (11, 80), (12, 85), (13, 90), (14, 95),
    (15, 100), (16, 95), (17, 90), (18, 85), (19, 80), (20, 75),
    (21, 70), (22, 65), (23, 60), (24, 55), (25, 50), (26, 45), (27, 40), (28, 35);

EXEC dbo.sp_upsert_fish_lunar_catch_probability 
    @fish_id = '5d069a33-6b36-4314-bd49-8a32a6c92245',
    @probabilities = @probs;    


    Alternative procedure that accepts a fish ID and a table-valued parameter (TVP) containing day and probability values. 
    The procedure will validate the input, then use a MERGE statement to insert or update the probabilities in the fish_lunar_catch_probability table. 
    It will return the number of rows affected.
*/

CREATE TYPE dbo.DailyProbabilityType AS TABLE
(
    [day]       tinyint NOT NULL PRIMARY KEY,
    probability smallint NOT NULL
);
GO

-- Step 2: Create the stored procedure using TVP
IF OBJECT_ID('dbo.sp_upsert_fish_lunar_catch_probability', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_upsert_fish_lunar_catch_probability;
GO

CREATE PROCEDURE dbo.sp_upsert_fish_lunar_catch_probability
(
    @fish_id uniqueidentifier,
    @probabilities dbo.DailyProbabilityType READONLY
)
AS
SET NOCOUNT ON
BEGIN TRY

    -- Validate fish_id exists
    IF NOT EXISTS (SELECT 1 FROM dbo.fish WHERE fish_id = @fish_id)
    BEGIN
        RAISERROR('Fish ID does not exist in fish table', 16, 1);
        RETURN;
    END

    -- Validate day range (1-28)
    IF EXISTS (SELECT 1 FROM @probabilities WHERE [day] < 1 OR [day] > 28)
    BEGIN
        RAISERROR('Day values must be between 1 and 28', 16, 1);
        RETURN;
    END

    -- Validate probability range (0-100)
    IF EXISTS (SELECT 1 FROM @probabilities WHERE probability < 0 OR probability > 100)
    BEGIN
        RAISERROR('Probability values must be between 0 and 100', 16, 1);
        RETURN;
    END

    -- MERGE to insert or update
    MERGE INTO dbo.fish_lunar_catch_probability AS target
    USING @probabilities AS source
    ON target.fish_id = @fish_id AND target.[day] = source.[day]
    WHEN MATCHED THEN
        UPDATE SET target.probability = source.probability
    WHEN NOT MATCHED THEN
        INSERT (fish_id, [day], probability)
        VALUES (@fish_id, source.[day], source.probability);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spPersistIpBan' AND type = 'P')
    DROP PROCEDURE dbo.spPersistIpBan
GO

CREATE PROCEDURE [dbo].spPersistIpBan (@counterPage int, @agent nvarchar(255), @host nvarchar(255), @ip4 varchar(15), @startPage nvarchar(255), @baned bit, @id uniqueidentifier)
AS
SET NOCOUNT ON
	BEGIN TRY 
	 UPDATE SessionHandler SET counterPage = @counterPage, userAgent = @agent, host = @host, baned = 1 WHERE (@ip4 <> '' AND ip4 = @ip4)
     IF @@ROWCOUNT > 0
     BEGIN
        RETURN;
     END
     INSERT INTO SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage) VALUES (@id, @agent, @host, @startPage, @baned, @ip4, @counterPage)
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;          
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'spRegisterPageHit' AND type = 'P')
    DROP PROCEDURE dbo.spRegisterPageHit
GO

CREATE PROCEDURE [dbo].spRegisterPageHit(@counterPage int, @agent nvarchar(255), @host nvarchar(255), @ip4 varchar(15), @startPage nvarchar(255), @baned bit, @id uniqueidentifier)
AS
SET NOCOUNT ON
	BEGIN TRY 
	 UPDATE SessionHandler SET counterPage = ISNULL(counterPage, 0) + @counterPage, userAgent = @agent, host = @host, startPage = @startPage, baned = 0 WHERE activityDate = CAST(GETUTCDATE() AS date) AND (@ip4 <> '' AND ip4 = @ip4)
     IF @@ROWCOUNT > 0
     BEGIN
        RETURN;
     END
     INSERT INTO SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage) VALUES (@id, @agent, @host, @startPage, @baned, @ip4, @counterPage)
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;          
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------

