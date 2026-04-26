IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'vw_NewID' AND type = 'V')
    DROP VIEW dbo.vw_NewID
GO
CREATE VIEW dbo.vw_NewID 
WITH SCHEMABINDING 
AS 
    SELECT newid() AS new_id
GO

------------------------------------------------------------------------------
/**
 * @table global_configuration
 * @brief Stores global system configuration as key–value pairs.
 *
 * This table contains application-wide configuration settings, including
 * default values, user attribution, update timestamps, and system flags.
 * It is used for both static configuration (feature flags, settings) and
 * dynamically maintained values (e.g., counters, metrics).
 */
------------------------------------------------------------------------------

CREATE TABLE global_configuration
(
	config_attribute                varchar(50) NOT NULL,    -- Unique configuration key (Primary Key)
	config_value                    nvarchar(max) NULL,      -- Current value of the configuration setting.
	global_config_default_value     nvarchar(max) NULL,      -- Default value used when no explicit value is provided.
	global_config_user_name         nvarchar(128) NULL,      -- Username of the last user who modified this configuration.
	global_config_updatedate        datetime2 NOT NULL,      -- Timestamp of the last update. Defaults to GETDATE().
	global_config_type              varchar(16) NULL,        -- Optional type classification (e.g., 'int', 'string', 'json', 'bool').
	global_configuration_sysflag    bit NOT NULL,            -- System flag indicating internal configuration: 1 = system-managed  0 = user-managed (default)
    CONSTRAINT pk_core_configuration PRIMARY KEY CLUSTERED (config_attribute)
)
GO

ALTER TABLE dbo.global_configuration ADD  CONSTRAINT DEF_global_config_date  DEFAULT (getdate()) FOR global_config_updatedate
GO

ALTER TABLE dbo.global_configuration ADD  CONSTRAINT DEF_global_config_flag  DEFAULT (0) FOR global_configuration_sysflag
GO

IF NOT EXISTS (SELECT * FROM global_configuration WHERE config_attribute = 'counter')
   INSERT INTO global_configuration (config_attribute, config_value) VALUES ('counter', '6000')
ELSE
   UPDATE global_configuration SET config_value = (SELECT 500000 + SUM(UniqueIPCount) FROM (SELECT COUNT(DISTINCT ipAddr) AS UniqueIPCount FROM SessionHandler GROUP BY CAST(startSess AS DATE) )t)
   WHERE config_attribute = 'counter'
GO

IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_newid')
    DROP FUNCTION dbo.fn_newid
GO

/*
    SELECT dbo.fn_newid()
*/

CREATE FUNCTION dbo.fn_newid()
RETURNS uniqueidentifier
WITH SCHEMABINDING 
BEGIN
    DECLARE @result uniqueidentifier = (SELECT new_id FROM dbo.vw_NewID)
	DECLARE @node_id char(1) = (SELECT UPPER(LEFT(config_value, 1)) FROM dbo.global_configuration WHERE config_attribute = 'node')
    IF @node_id Is NULL OR @node_id NOT IN ('0', '1', '2', '3', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F')
        RETURN @result
    DECLARE @uuid varchar(36) = UPPER(CAST(@result AS varchar(36)));
    RETURN CAST(LEFT(@uuid, 14) + @node_id + RIGHT(@uuid, 21) AS uniqueidentifier);
END
GO

CREATE TABLE access_point
(
    uuid        uniqueidentifier NOT NULL CONSTRAINT DF_access_point_uuid DEFAULT(dbo.fn_newid()),
    OFGID       int NULL,
    pointType   nvarchar(255) NULL,
    lastVerif   nvarchar(255) NULL,
    verifSrc    nvarchar(255) NULL,
    Parking     nvarchar(255) NULL,
    ownerType   nvarchar(255) NULL,
    matType     nvarchar(255) NULL,
    accessType  nvarchar(255) NULL,
    userFee     nvarchar(255) NULL,
    visibility  nvarchar(255) NULL,
    siteName    nvarchar(255) NULL,
    photoUrl    nvarchar(255) NULL,
    country     char(2) NULL,
    state       char(2) NULL,
    create_stamp  datetime2 NOT NULL   CONSTRAINT DF_access_point_stamp DEFAULT(CURRENT_TIMESTAMP),
    update_stamp  datetime2,
    update_by  nvarchar(255),
    CONSTRAINT PK_access_point_uuid  PRIMARY KEY ( uuid ),
    CONSTRAINT UK_access_point       UNIQUE      ( country, state, siteName )
);
GO

-- alter table access_point add access_point_id UniqueIdentifier NOT NULL default newid() with values
-- ALTER TABLE access_point ADD CONSTRAINT PK_access_point PRIMARY KEY (uuid);

CREATE TABLE CanPostLatLon
(
    [lat] [real] NULL,
    [lon] [real] NULL,
    [postal] [char](6) NOT NULL
);
GO

ALTER TABLE CanPostLatLon ADD CONSTRAINT PK_CanPostLatLon PRIMARY KEY CLUSTERED (postal);
GO

CREATE TABLE City
(
    City_id     int NOT NULL,
    place       nvarchar(128) NOT NULL,
    county      nvarchar(64) NOT NULL,
    [state]     varchar(16) NOT NULL,
    lat         float not null default(0.0),
    lon         float not null default(0.0),
    country     char(2),
    region      int not null default(-1),                  -- region state like 'Eastern Ontario'
    stamp       datetime2 NOT NULL DEFAULT( GETUTCDATE() ),
    population  int
);
GO
ALTER TABLE City ADD CONSTRAINT PK_City PRIMARY KEY CLUSTERED (City_id);
GO
-------------------------------------------------------------------------------------------------------
CREATE TABLE Country
(
    Country_id      char(4) NOT NULL,
    Country_name    varchar(64) NOT NULL,
    picture         varbinary(max) NULL
);
GO
ALTER TABLE Country ADD CONSTRAINT PK_Country PRIMARY KEY CLUSTERED (Country_id);
GO
-------------------------------------------------------------------------------------------------------
CREATE TABLE County
(
   County       varchar(50) NOT NULL,
   Country      char(2) NOT NULL DEFAULT(''),
   State_Id     int   NOT NULL,
   County_ID    int   ,
   state        char(2)   NOT NULL,
);
GO
------------------------------keep current water state--------------------------------
-- based on aggregation of latest 3 day's data from USWater.dbo.vUSWaterData
CREATE TABLE CurrentWaterState
(
    mli            varchar(64) NOT NULL,
    stamp          datetime2 NOT NULL,    -- actual data reading on  site mli
    temperature    float,
    discharge      float,
    turbidity      float,
    oxygen         float,
    ph             float, 
    elevation      float,
    sid            bigint not null,    -- sid comes from 
    velocity       float,
    iterstamp      datetime2 NOT NULL DEFAULT(GETUTCDATE())
);
GO
ALTER TABLE CurrentWaterState ADD CONSTRAINT PK_CurrentWaterState PRIMARY KEY CLUSTERED (mli);
GO
--------------------------------------------------------------------------------------------
if object_id('TR_CurrentWaterState') is not null drop TRIGGER TR_CurrentWaterState
GO

CREATE TRIGGER TR_CurrentWaterState ON CurrentWaterState 
FOR UPDATE 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime2, @mli varchar(64) 

    SELECT @stamp = stamp, @mli=mli FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
        UPDATE WaterStation SET updData =  @stamp 
          WHERE mli=@mli   
    END
END
GO    
--------------------------------------------------------------------------------------------
CREATE TABLE fish_family
(
    Family_id    uniqueidentifier NOT NULL,
    Family_name  varchar(64) NOT NULL,
    link         varchar(64) NULL,
    fid          int NOT NULL,
    descr        nvarchar(max) NULL,
    created      datetime2 NOT NULL 
)
GO
ALTER TABLE fish_family ADD CONSTRAINT PK_Family PRIMARY KEY CLUSTERED (Family_id) ;
ALTER TABLE fish_family add constraint df_Family_Id default NEWSEQUENTIALID() for Family_id;
ALTER TABLE fish_family add constraint df_Family_created default getdate() for created;
GO

--insert into fish_family (Family_id, Family_name, fid, created) VALUES ('00000000-0000-0000-0000-000000000000', 'none', 100001, GETUTCDATE());
------------------------------------------------------------------------------

CREATE TABLE fish 
(
    fish_id         uniqueidentifier  NOT NULL,
    fish_name       varchar (32) NOT NULL,
    fish_latin      varchar (64) NOT NULL,
    alt_name        nvarchar(max),
    descrip         nvarchar(max) NULL,
    family_Id       uniqueidentifier NOT NULL DEFAULT('00000000-0000-0000-0000-000000000000'),
    img             varbinary(max),
    fish_Type       int default(255),         -- 1 - sport, 2 - commercial, 4 - invading, 8 - aquarium
    water_type      int,                      -- 1 - Freshwater, 2 - Saltwater, 4 - Clear water, 8 - Low velocity, 16 - Moderate velocity, 32 - High velocity, 64 - Turbid waters, 128 - Moderately Turbid waters
    food_Type       int default(0),           -- 1 - Aquatic Insects, 2 - Terrestrial Insects, 4- Fish eggs, 8 - Crustaceans, 16 - Small Fish, Terrestrial Animals - 32, 64 - Cannibals
    react_color     int default(0),
    food_habitat    int,
    terrestrial_insects int default(0),       -- 1 - Silverfish, 2 - Dragonflies, 4 - Crickets, 8 - Earwigs, 16 - Cicadas, 32 - True Bugs, 64 - Lacewings, 128 - Beetles, 256 - Butterflies, 512 - Flies, 1024 - Sawflies
    crustaceans     int default(0),           -- 1 - Crabs, 2 - Lobsters, 4 - Crayfish, 8 - Shrimp, 16 - Krill, 32 - Barnacles, 64 - Larvae, 128 - Woodlice, 256 - Sandhoppers, 512 - Amphipods, 1024 - Conchostraca
    terrestrial_animals int default(0),       -- 1 - Birds, 2 - Snakes, 4 - Snails, 8 - Slugs 
    node_food_habitat nvarchar(max),
    synonims        nvarchar (255) NULL,
    numRuls         int,                      -- 1 - temperature, 2 - turbidity, 4 - oxygen, 8 - ph
    pic             varbinary(max),
    aquatic_insects int default(0),           -- 1 - Collembola, 2 - Ephemeroptera, 4 - Odonata, 8 - Plecoptera, 16 - Megaloptera, 32- Neuroptera, 64 - Coleoptera, 128 - Hemiptera, 256 - Hymenoptera, 512 - Diptera, 1024 - Mecoptera, 2048 - Lepidoptera, 4096 - Trichoptera
    food            nvarchar(255),
    periodStartII   datetime2,
    periodEndII     datetime2,
    link            nvarchar(255),
    feedsOver       nvarchar(255),
    fish_ability    int,                      -- 1 - Moon Sensitivity, 2 - Migration Pattern
    habitat         nvarchar(255),
    fish_moon_sensitive bit,
    fish_migrate_pattern bit,
    locked          bit default(0),
    editor          uniqueidentifier,
    sid             int not null identity(1,1),
    fish_home_range float,                -- [km]
    created         datetime2 not null default(getutcdate()),
    stamp           datetime2 not null default(getutcdate())
);
GO

ALTER TABLE fish ADD PRIMARY KEY CLUSTERED (fish_id);
GO
ALTER TABLE fish add constraint df_fish_id default NEWSEQUENTIALID() for fish_id;
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_fish_Latin ON fish(fish_Latin)    
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_fish_name  ON fish(fish_name)    
GO
ALTER TABLE fish ADD CONSTRAINT FK_fish_Family FOREIGN KEY (family_Id) REFERENCES fish_family(family_Id) ON DELETE CASCADE ON UPDATE CASCADE;
GO

CREATE TRIGGER TR_ins_Fish ON fish
 FOR INSERT
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    
    INSERT fish_Rule  ([fish_Id],[periodStart],[periodEnd], stamp)
      SELECT  fish_Id, -1 as  periodStart,  -1 as  periodEnd, getutcdate()  FROM INSERTED d
        WHERE NOT EXISTS (SELECT * FROM fish_Rule fr WHERE fr.fish_id = d.fish_id and fr.periodStart = -1 and fr.periodEnd = -1)
    INSERT fish_Rule  ([fish_Id],[periodStart],[periodEnd], stamp)
      SELECT  fish_Id, 1 as  periodStart,  2 as  periodEnd, getutcdate()  FROM INSERTED d
        WHERE NOT EXISTS (SELECT * FROM fish_Rule fr WHERE fr.fish_id = d.fish_id and fr.periodStart <> -1 and fr.periodEnd <> -1)

    update r SET r.stamp = getutcdate() FROM  inserted i JOIN fish r ON (i.fish_id=r.fish_id)
END
GO
------------------------------------------------------------------------------
CREATE TABLE fish_image 
(
    fish_id             uniqueidentifier NOT NULL,
    fish_image_gender   bit,
    fish_image_pic      varbinary(max) NOT NULL,
    fish_image_id       int NOT NULL identity(1,1),
    fish_image_source   nvarchar(255) NOT NULL,
    fish_image_author   nvarchar(255) NOT NULL,
    fish_image_link     nvarchar(256) NOT NULL ,
    fish_image_label    nvarchar(256) NULL,
    fish_image_location nvarchar(256) NULL,
    fish_image_lat      float,
    fish_image_lon      float,
    fish_image_tag      nvarchar(256) NULL,
    fish_image_hash     varbinary(256) NOT NULL CONSTRAINT UK_fish_image UNIQUE,  -- hash to prevent duplicates
    fish_image_stamp    datetime2 not null      CONSTRAINT df_fish_image_stamp DEFAULT GETUTCDATE(),
    PRIMARY KEY CLUSTERED (    fish_image_id ASC ) ON [PRIMARY]
) 
GO
CREATE NONCLUSTERED INDEX UK_fish_image_ID ON fish_image(fish_id)    
GO
ALTER TABLE fish_image  WITH CHECK ADD FOREIGN KEY(fish_id) REFERENCES fish(fish_id)
GO
------------------------------------------------------------------------------
if object_id('TR_fish_image') is not null drop TRIGGER TR_fish_image
GO

CREATE TRIGGER dbo.TR_fish_image ON dbo.fish_image
 FOR INSERT, UPDATE
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    
   UPDATE t SET t.fish_image_hash = HASHBYTES('SHA1', t.fish_image_pic) FROM fish_image t JOIN INSERTED i ON t.fish_id = i.fish_id
END
GO
------------------------------------------------------------------------------
CREATE TABLE fish_zoo
(
    [fish_id] [uniqueidentifier] NOT NULL,

    fish_max_length   float,                   -- cm
    fish_avg_length   float,                   -- cm
    fish_max_weight   float,                   -- kg
    fish_avg_weight   float,                   -- kg
    [fin] [nvarchar](max) NULL,
    [body] [nvarchar](max) NULL,
    Longevity int,   -- years
    coloration [nvarchar](max) NULL,           -- 10-12 dark bars on side
    Counts [nvarchar](max) NULL,               -- 12 dorsal fin soft rays; 22-28 scales around caudle peduncle; 7-10 scales above lateral line;
    shape  [nvarchar](max) NULL,               -- Moderately compressed, elongate body; large mouth 
    external_morphology [nvarchar](max) NULL,  -- : Shortest dorsal fin spine contained 1.1 to 2.5 times in longest dorsal spine
    internal_morphology [nvarchar](max) NULL,  -- Pyloric caecae not branched
    natural_color int default(0),
    fish_zoo_image    int,              -- index id for fish image    
    [link] [nvarchar](256) NULL,
    stamp datetime2 not null CONSTRAINT df_fish_zoo_stamp DEFAULT GETUTCDATE(),
    PRIMARY KEY CLUSTERED (    [fish_id] ASC ) ON [PRIMARY]
) 
GO
ALTER TABLE [dbo].fish_zoo  WITH CHECK ADD FOREIGN KEY([fish_id]) REFERENCES [dbo].[fish] ([fish_id])
GO
ALTER TABLE dbo.fish_zoo  WITH CHECK ADD FOREIGN KEY(fish_zoo_image) REFERENCES dbo.fish_image (fish_image_id)
GO
CREATE NONCLUSTERED INDEX idx_fish_zoo_len ON [dbo].fish_zoo (fish_max_length ASC ) ON [PRIMARY]
GO
------------------------------------------------------------------------------
CREATE TABLE fish_spawn
(
    fish_id                 uniqueidentifier NOT NULL,
    fish_spawn_eggs_min     int, 
    fish_spawn_eggs_max     int, 
    fish_spawn_location     nvarchar(max),
    fish_spawn_description  nvarchar(max),
    reproductive_strategy   nvarchar(max),
    fish_spawn_age_male     int,  -- years when can spawn
    fish_spawn_age_female   int,  -- years when can spawn
    fish_spawn_stamp datetime2 not null CONSTRAINT df_fish_spawn_stamp DEFAULT GETUTCDATE(),
    PRIMARY KEY CLUSTERED (    [fish_id] ASC ) ON [PRIMARY]
) 
GO
ALTER TABLE fish_spawn  WITH CHECK ADD FOREIGN KEY(fish_id) REFERENCES fish (fish_id)
GO
-------------------------------------------------------------------------------------------------------------------------
CREATE TABLE fish_predator
(
    fish_id     uniqueidentifier NOT NULL,
    predator_id uniqueidentifier NOT NULL,
    age_year int,
    stamp datetime2 not null default (getdate()),
    PRIMARY KEY CLUSTERED (    fish_id, predator_id ASC ) ON [PRIMARY],
) 
GO
ALTER TABLE fish_predator  WITH CHECK ADD FOREIGN KEY([fish_id]) REFERENCES fish ([fish_id])
GO

ALTER TABLE fish_predator  WITH CHECK ADD FOREIGN KEY(predator_id) REFERENCES fish ([fish_id])
GO

ALTER TABLE fish_predator ADD CONSTRAINT CH_fish_predator CHECK (fish_id != predator_id)
GO

------------------------------------------------------------------------------
-- if start and end -1 then general data (1:1 to fish and must be presented) otherwise spawn periods
CREATE TABLE fish_Rule
(
    fish_Id     uniqueidentifier NOT NULL,
    id          uniqueidentifier not null,
    parent_id   uniqueidentifier,
    lake_id     uniqueidentifier,
    periodStart int NOT NULL default(-1),  -- -1 default period or if positive then month
    periodEnd   int NOT NULL default(-1),  -- -1 default period
    habitat     int  default(0),             
    feedsOver   int default(0),  -- 1 - rock, 2 - gravel, 4 - sand, 8- mud, 16 - grass, 32 - rubble,
                                -- 64 - boulder, 128 - silt,  256 - cobble, 1024 - LimeStone, 2048 -     threatened   int,           --   status(1=non-threatened, 2=threatened)
    react_color int default(0),
    spawnsOver  int default(0),           -- 1 - rock, 2 - gravel, 4 - sand, 8- mud, 16 - grass
    spawnsIn    int default(0),           -- as     
    hatch_egg_month tinyint,               -- Eggs hatch in March. [1-12]
    stamp       datetime2 not null default(getutcdate()),
    editor      uniqueidentifier,
    locked      bit default(0),
    link        nvarchar(255)
)
GO

ALTER TABLE fish_Rule ADD CONSTRAINT PK_fish_Rule_fish_id PRIMARY KEY CLUSTERED (id);
GO
ALTER TABLE fish_Rule add constraint df_fish_Rule_id default NEWSEQUENTIALID() for id;
GO
ALTER TABLE fish_Rule ADD CONSTRAINT UK_fish_Rule UNIQUE NONCLUSTERED (fish_Id, periodStart, periodEnd);
GO
ALTER TABLE fish_Rule ADD CONSTRAINT FK_fish_Rule_Fish FOREIGN KEY (fish_Id) 
   REFERENCES fish(fish_id)
GO
CREATE NONCLUSTERED INDEX IDX_fish_rule ON [dbo].[fish_Rule] ([periodStart],[periodEnd]) INCLUDE ([fish_Id],[habitat])
GO
------------------------------------------------------------------------------
if object_id('TR_iFish_rule') is not null drop TRIGGER TR_iFish_rule
GO

CREATE TRIGGER dbo.TR_iFish_rule ON dbo.fish_Rule
 FOR INSERT, UPDATE
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    
  INSERT fish_Rule  ([fish_Id],[periodStart],[periodEnd])
      SELECT [fish_Id], 4 as periodStart , 6 as periodEnd FROM INSERTED  r WHERE  -1 = r.periodStart AND -1 = r.periodEnd 
       AND NOT EXISTS (SELECT * FROM fish_Rule fr WHERE fr.fish_id = r.fish_id AND 0 < fr.periodStart AND 0 < fr.periodEnd )
  update r SET r.stamp = getutcdate() FROM  inserted i JOIN fish_Rule r ON (i.fish_id=r.fish_id)
END
GO
------------------------------------------------------------------------------
-- select r.* from real_interval r join fish_rule f on f.id=r.ri_parent_id where f.fish_Id='6b45fea3-5cbe-4982-89af-c241eb5c6a36'
CREATE TABLE real_interval
(
    ri_parent_id uniqueidentifier NOT NULL,
    ri_type      tinyint NOT NULL,  -- 2 -depth spawn, 3 - hab depth, 8 - ph spawn, 9 - ph hab, 16 - temperature spawn, 17 - temperature hab, 24 - turbidity spawn, 25 - turbidity hab
                                    -- 32 - oxygen spawn, 33 - oxygen hab, 40 - velocity spawn, 41 - velocity hab, 48 - salnity spawn, 49 - salnity hab
                                    -- , 56 - phosphat spawn, 57 - phosphat hab, 64 - nitrate spawn, 65 - nitrate hab
    ri_min       float,
    ri_low       float,
    ri_avg       float,
    ri_high      float,
    ri_max       float,
    ri_stamp     datetime2 not null CONSTRAINT df_real_interval_stamp DEFAULT GETUTCDATE()
)
GO
ALTER TABLE real_interval ADD CONSTRAINT PK_real_interval_parent_id PRIMARY KEY CLUSTERED (ri_parent_id, ri_type);
GO
ALTER TABLE real_interval ADD CONSTRAINT CH_real_interval CHECK 
(
    ( CASE WHEN ri_min IS NULL  OR ri_low IS NULL  THEN 0 WHEN ri_min >  ri_low THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_min IS NULL  OR ri_avg IS NULL  THEN 0 WHEN ri_min >  ri_avg THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_min IS NULL  OR ri_high IS NULL THEN 0 WHEN ri_min >  ri_high THEN 1 ELSE 0 END)  = 0
    AND
    ( CASE WHEN ri_min IS NULL  OR ri_max IS NULL  THEN 0 WHEN ri_min >  ri_max THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_low IS NULL  OR ri_avg IS NULL  THEN 0 WHEN ri_low >  ri_avg THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_low IS NULL  OR ri_high IS NULL THEN 0 WHEN ri_low >  ri_high THEN 1 ELSE 0 END)  = 0
    AND
    ( CASE WHEN ri_low IS NULL  OR ri_max IS NULL  THEN 0 WHEN ri_low >  ri_max THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_avg IS NULL  OR ri_high IS NULL THEN 0 WHEN ri_avg >  ri_high THEN 1 ELSE 0 END)  = 0
    AND
    ( CASE WHEN ri_avg IS NULL  OR ri_max IS NULL  THEN 0 WHEN ri_avg >  ri_max THEN 1 ELSE 0 END)   = 0
    AND
    ( CASE WHEN ri_high IS NULL OR ri_max IS NULL  THEN 0 WHEN ri_high > ri_max THEN 1 ELSE 0 END)   = 0
);
GO
ALTER TABLE real_interval  WITH CHECK ADD FOREIGN KEY(ri_parent_id) REFERENCES fish_Rule (id)
GO
-- used in fn_get_koef_fish_station_temperature
CREATE NONCLUSTERED INDEX IDX_real_interval ON [dbo].[real_interval] ([ri_type]) INCLUDE ([ri_min],[ri_max])
GO

--delete from real_interval where ri_parent_id not in (select id from fish_Rule)

-- insert into real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max) select id, 56, saltL, null, null, null, saltH from fish_Rule where periodStart<>-1 and periodEnd<>-1
-- insert into real_interval (ri_parent_id, ri_type, ri_min, ri_low, ri_avg, ri_high, ri_max) select id, 57, saltL, null, null, null, saltH from fish_Rule where periodStart=-1 and periodEnd=-1

------------------------------------------------------------------------------
-- fishing  spot
CREATE TABLE fish_Spot
(
    Spot_id     uniqueidentifier default NEWSEQUENTIALID() NOT NULL,
    fish_id     uniqueidentifier NOT NULL,
    lat         float NOT NULL DEFAULT(0),
    lon         float NOT NULL DEFAULT(0),
    lake_id     uniqueidentifier,
    author      varchar(64),
    length      float,                                  -- in sm
    weight      float,                                  -- in gramm
    created     datetime2 NOT NULL DEFAULT getdate(),
    comment     nvarchar(max),
    picId       varbinary(max),
    spot_sid    int not null identity(1,1)
);
GO
ALTER TABLE fish_Spot ADD CONSTRAINT PK_fish_Spot PRIMARY KEY CLUSTERED (Spot_id);
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- fishing  catch probability based on spawn activity
CREATE TABLE dbo.fish_catch_probability
(
    fish_id     uniqueidentifier NOT NULL,  -- fish id
    month       tinyint NOT NULL,           -- month number 1..12 
    probability smallint NOT NULL,          -- probability 0 - 500%
    
    -- Primary key constraint
    CONSTRAINT PK_fish_catch_probability PRIMARY KEY CLUSTERED (fish_id, month),
    
    -- Foreign key to fish table
    CONSTRAINT FK_fish_catch_probability_fish FOREIGN KEY (fish_id) 
        REFERENCES dbo.fish(fish_id)
        ON DELETE CASCADE 
        ON UPDATE CASCADE,
    
    -- Check constraint for month (1-12)
    CONSTRAINT CK_fish_catch_probability_month 
        CHECK (month >= 1 AND month <= 12),
    
    -- Check constraint for probability (0-500)
    CONSTRAINT CK_fish_catch_probability_probability 
        CHECK (probability >= 0 AND probability <= 500)
);
GO
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- fishing  catch probability based on spawn activity
CREATE TABLE dbo.fish_lunar_catch_probability
(
    fish_id     uniqueidentifier NOT NULL,  -- fish id
    day         tinyint          NOT NULL,  -- month number 1..28 
    probability smallint         NOT NULL,  -- probability 0 - 100%
    
    -- Primary key constraint
    CONSTRAINT PK_fish_lunar_catch_probability PRIMARY KEY CLUSTERED (fish_id, day),
    
    -- Foreign key to fish table
    CONSTRAINT FK_fish_lunar_catch_probability_fish FOREIGN KEY (fish_id) 
        REFERENCES dbo.fish(fish_id)
        ON DELETE CASCADE 
        ON UPDATE CASCADE,
    
    -- Check constraint for day (1-28)
    CONSTRAINT CK_fish_lunar_catch_probability_day 
        CHECK (day >= 1 AND day <= 28),
    
    -- Check constraint for probability (0-100)
    CONSTRAINT CK_fish_lunar_catch_probability 
        CHECK (probability >= 0 AND probability <= 100)
);
GO
------------------------------------------------------------------------------
CREATE TABLE dbo.fishingAccessPoint
(
    [OFGID] [int] NULL,
    [pointType] [nvarchar](255) NULL,
    [lastVerif] [nvarchar](255) NULL,
    [verifSrc] [nvarchar](255) NULL,
    [Parking] [nvarchar](255) NULL,
    [ownerType] [nvarchar](255) NULL,
    [matType] [nvarchar](255) NULL,
    [accessType] [nvarchar](255) NULL,
    [userFee] [nvarchar](255) NULL,
    [visibility] [nvarchar](255) NULL,
    [siteName] [nvarchar](255) NULL,
    [photoUrl] [nvarchar](255) NULL,
    [infoUrl] [nvarchar](255) NULL,
    [comments] [nvarchar](255) NULL,
    [geoUpdDt] [int] NULL,
    [effDate] [int] NULL
)
GO
------------------------------------------------------------------------------------

if object_id('dbo.GeoIP') is not null 
    drop TABLE dbo.GeoIP
GO

CREATE TABLE GeoIP
(
    id int not null  identity(1,1),
    nsi char(16) NOT NULL,
    mask int NULL,
    postal varchar(16) NOT NULL,
    latitude float NOT NULL,
    longitude float NOT NULL,
    ip4 binary(4) NOT NULL  DEFAULT(0)
)
GO 
ALTER TABLE GeoIP ADD CONSTRAINT PK_GeoIP PRIMARY KEY CLUSTERED ([ID] ASC) ON [PRIMARY]    
GO
CREATE NONCLUSTERED INDEX [idx_GeoIP_lat] ON GeoIP (latitude ASC)  
CREATE NONCLUSTERED INDEX [idx_GeoIP_lon] ON GeoIP (longitude ASC) 
CREATE NONCLUSTERED INDEX [idx_GeoIP_ip4] ON GeoIP (ip4 ASC) 

------------------------------------------------------------------------------
CREATE TABLE dbo.lake_image
(
    lake_image_id int NOT NULL identity(1,1),
    lake_image_ownerid	uniqueidentifier,        
    lake_image_pic		varbinary(max) NOT NULL,
    lake_image_source	nvarchar(255) NOT NULL,
    lake_image_author	nvarchar(255) NOT NULL,
    lake_image_link		nvarchar(256) NOT NULL ,
    lake_image_label	nvarchar(256) NULL,
    lake_image_location nvarchar(256) NULL,
    lake_image_lat		float,
    lake_image_lon		float,
	lake_image_type		int,				-- 0 - link, 1 - jpg, 2 - png, 8 - pdf, 9 - word, 10 - xls
	lake_image_map      int,                -- 1 - map 
    lake_image_tag		nvarchar(256) NULL,
    lake_image_hash		varbinary(256) NOT NULL CONSTRAINT UK_lake_image UNIQUE,  -- hash to prevent duplicates
    lake_image_stamp	datetime2 not null  CONSTRAINT df_lake_image_stamp DEFAULT GETUTCDATE(),
    PRIMARY KEY CLUSTERED (    lake_image_id ASC ) ON [PRIMARY]
) 
GO
CREATE UNIQUE INDEX [UX_lake_image_ownerid] ON lake_image (lake_image_ownerid) 
GO
------------------------------------------------------------------------------
--  1 - lake, 2 - river,  4 - stream, 8 - pond, 16 - marsh, 32 - backwater, 64 - creek
--  128 - canal, 256 - Estuary, 512 - shore, 1024 - drain, 2048 - ditch, 4096 = Wetland,  8192 - Reservoir, 16385 - Sea
CREATE TABLE water_body
(
    en			varchar(32) NOT NULL,		-- for example: lake
    fr			nvarchar(32) NOT NULL,		-- for example: lac	
	locType		int  NOT NULL,				-- 1, 2, 4, 8, ...
	speed		int  NOT NULL,				-- 0 - lake, 1 - slow moving, 4 - normal moving, 8 - stream, 16- fast stream
	description varchar(255),
    gw			nvarchar(32),		        -- for example: Viteetshìk
    PRIMARY KEY CLUSTERED ( en )
) 
GO
/*
INSERT INTO Lake (Lake_id, stamp, locType, lake_name, Alt_Name, french_name, native, source, mouth, link, length, depth, width, locked, old_id
    , editor, basin, descript, watershield, regulations, link_reg, drainage, Discharge, fishing, Volume, Shoreline, surface
    , lake_road_access, isFish, noFish, is_fishing_prohibited, isWell, CGNDB, geom) 
    VALUES ('22222222-2222-2222-2222-2222222222222', '19690929', 2, 'Test River', N'Alt_Name', N'french_name', N'native'
    , '11111111-1111-1111-1111-1111111111111', '22222222-2222-2222-2222-2222222222222', N'http://fishfind.info', 100, 100, 100, 1, 'CCCP'
    , '00000000-0000-0000-0000-000000000000', 'basin', 'descript', 'watershied', 'regulations', '00000000-0000-0000-0000-000000000000', 'drainage', 'Discharge', 'fishing', 100, 100, 100
    , 'lake_road_access', 1, 0, 1, 1, 'GKMZA', NULL)
*/
-- update Lake set locType = 64 where lake_name like '% Greek'
------------------------------------------------------------------------------
CREATE TABLE Lake
(
    Lake_id     uniqueidentifier   NOT NULL,
    stamp       DATETIME2,
    locType     int NOT NULL DEFAULT(0),     
    lake_name   nvarchar (64) NOT NULL,
    Alt_Name    nvarchar (64),              -- alternative name
    french_name nvarchar (128),             -- alternative name
    native      nvarchar (64),              -- lake name in native meaning
    source      uniqueidentifier,
    mouth       uniqueidentifier,
    link        nvarchar(max),
    length      int,                        -- km
    depth       int,                        -- m
    width       int,                        -- km
    locked      bit,
    old_id      varchar(64),
    editor      uniqueidentifier,
    basin       varchar(64),
    descript    nvarchar(max),
    sid         int not null IDENTITY(1,2),
    watershield nvarchar (128),             -- watershield name
    regulations nvarchar(255),
    link_reg    nvarchar(255),              -- link to regulations
    drainage    nvarchar(128),
    Discharge   nvarchar(128),
    fishing     nvarchar(max),
	isolated    bit,                    -- has not water connections to other lakes
    lake_road_access nvarchar(max),
    isFish      bit,                    -- if fish was linked (updated from trigger on lake_fish)
    noFish      bit,                    -- dead lake no fish can live
    is_fishing_prohibited bit,          -- fishing in this lake is prohibited
    isWell      bit,                    -- if river has monitored well (updated from trigger on WaterStation)
    Volume      int,                    -- km^3
    Shoreline   int,                    -- km
    surface     int,                    -- km^2
    CGNDB       char(5),                -- unique id on http://www4.rncan.gc.ca/search-place-names/unique
    geom        geography,
    symbol      nvarchar(1),            -- first letter of actual name (to speed up search)
    reviewed    bit,                    -- means review manually done by operator
    CONSTRAINT PK_LAke PRIMARY KEY CLUSTERED (Lake_id),
) ;
GO

-- delete from lake where lake_id = '00000000-0000-0000-0000-000000000000'
-- delete from Tributaries where '00000000-0000-0000-0000-000000000000' in (lake_id, main_lake_id)
-- update lake set stamp=getdate() where lake_id='64cf30df-2892-e811-9104-00155d007b12'
--delete from lake where lake_id = '67ECB996-F1A3-41C6-B0DF-AB512B732E60'
--delete from Tributaries where lake_id = '67ECB996-F1A3-41C6-B0DF-AB512B732E60'

ALTER TABLE Lake add constraint df_Lake_Id default NEWSEQUENTIALID() for Lake_id
GO  
ALTER TABLE Lake add constraint DF_lake_stamp default getutcdate() for stamp
GO
CREATE NONCLUSTERED INDEX [idx_Lake_sid] ON Lake (sid)
GO
CREATE INDEX [idx_Lake_stamp] ON Lake (lake_id, stamp)
GO
CREATE INDEX [idx_Lake_alt_name] ON Lake (alt_name) INCLUDE (lake_id) WHERE alt_name IS NOT NULL;
CREATE INDEX [idx_Lake_name] ON Lake (lake_name) INCLUDE (lake_id);
CREATE INDEX [idx_Lake_french_name] ON Lake (french_name) INCLUDE (lake_id)  WHERE french_name IS NOT NULL;
CREATE INDEX [idx_Lake_native] ON Lake (native) INCLUDE (lake_id)  WHERE [native] IS NOT NULL;
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_lake_CGNDB ON LAKE(CGNDB) WHERE CGNDB IS NOT NULL
GO
CREATE INDEX IDX_LAKE_TYPE ON Lake (locType) INCLUDE (lake_name, alt_Name, french_name, native, IsFish);
GO

CREATE TRIGGER TR_UPD_Lakes ON Lake
 FOR  UPDATE 
AS 
SET NOCOUNT ON
BEGIN
    UPDATE t SET t.stamp=getdate(), symbol = UPPER(LEFT(dbo.fn_clean_river_name(t.lake_name), 1))
        FROM lake t JOIN INSERTED i ON i.lake_id=t.lake_id

    UPDATE w SET w.locType = i.locType, w.lakeName=i.lake_name,
	 w.stamp = getdate()
      FROM WaterStation w, INSERTED i WHERE w.lakeid = i.lake_id
END
GO

CREATE TRIGGER TR_DEL_Lake ON [dbo].[Lake] 
 FOR  DELETE 
AS 
SET NOCOUNT ON
BEGIN
    DELETE FROM Tributaries WHERE lake_id IN (SELECT lake_id FROM DELETED)
    DELETE FROM lake_fish WHERE lake_id IN (SELECT lake_id FROM DELETED)
    DELETE FROM Lake_Shape WHERE lake_id IN (SELECT lake_id FROM DELETED)
    DELETE FROM Lake WHERE lake_id IN (SELECT lake_id FROM DELETED)
END
GO

CREATE TABLE Lake_State
(
    Lake_id     uniqueidentifier   NOT NULL,
	month       int                NOT NULL,
    PH          float,                         -- [7.0]  1..14
    Phosphorus  float,                         -- [mg/L] US EPA (1986) 0.01 - 0.03 mg/L - the level in uncontaminated lakes, 0.025 - 0.1 mg/L - level at which plant growth is stimulated    
                                               -- 0.1 mg/L - maximum acceptable to avoid accelerated eutrophication, > 0.1 mg/L - accelerated growth and consequent problems
    TDS         float,                         -- mg/L   ~596
	Conductivity float,                        -- uS/cm  ~955
	Alkalinity  float,                         -- mg/L   ~449
	Hardness    float,						   -- mg/L   ~372
	Sodium      float,					       -- mg/L   ~90
	Chloride    float,					       -- mg/l   ~11
	Bicarbonate float,                         -- mg/L   ~482
	Transparency float,						   -- [m]
	Oxygen      float,                         -- [mg/L]
	Salinity    float,                         -- 6
    clarity     float,                         -- Water Clarity [m]
	velocity    float,                         -- [m/s]
	water_degree float,
    air_degree   float,
	cold_cool    bit,                          -- 0 - cold, 1 - cool
	flow_stand   bit,                          -- 0 - flow, 1 - stand
    stamp       DATETIME2 NOT NULL DEFAULT(getdate()),
	PRIMARY KEY CLUSTERED ( Lake_id, month ),
	CONSTRAINT FK_Lake_State FOREIGN KEY (Lake_id) REFERENCES Lake(Lake_id) ON DELETE CASCADE ON UPDATE CASCADE
); 
GO

------------------------------------------------------------------------------
if object_id('TR_ui_Lake_State') is not null drop TRIGGER dbo.TR_ui_Lake_State
GO

CREATE TRIGGER TR_ui_Lake_State ON dbo.Lake_State
 FOR UPDATE, INSERT
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN TRY   
    UPDATE t SET t.stamp = getdate()
         -- The pH scale measures how acidic or basic a substance is. 
         -- The pH scale ranges from 0 to 14. A pH of 7 is neutral.
         , t.PH = (CASE WHEN i.PH < 0 OR ABS(i.PH) > 14 THEN NULL ELSE ABS(i.PH) END)  
         -- http://ceqg-rcqe.ccme.ca/download/en/205
         , t.Phosphorus = ABS(i.Phosphorus)             
        FROM Lake_State t JOIN INSERTED i ON i.lake_id = t.lake_id AND i.[month] = t.[month]
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()     AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , 'TR_ui_Lake_State' AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH;     
GO
------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- truncate table Lake_Shape
-- stores lake related shape files
CREATE TABLE Lake_Shape
(
    lake_id             uniqueidentifier NOT NULL,
    Lake_Shape_id       int not null identity,
    Lake_Shape_shape    geography NOT NULL,
    Lake_Shape_type     int,
    Lake_Shape_stamp    datetime2 NOT NULL default getutcdate(),
    Lake_Shape_idx      geometry,                  -- store box with boundaries
    Lake_Shape_hash     bigint,
    CONSTRAINT PK_Lake_Shape PRIMARY KEY CLUSTERED (Lake_id, Lake_Shape_id)
);
GO

CREATE NONCLUSTERED INDEX IDX_Lake_Shape ON  Lake_Shape (lake_id);
GO
ALTER TABLE Lake_Shape ADD CONSTRAINT FK_Lake_Shape FOREIGN KEY (lake_id) REFERENCES lake(lake_id) ON DELETE CASCADE ON UPDATE CASCADE;
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_Lake_Shape ON Lake_Shape(Lake_Shape_hash)
GO
-- ALTER TABLE Lake_Shape ADD CONSTRAINT PK_Lake_Shape PRIMARY KEY CLUSTERED (lake_id, Lake_Shape_id);
GO

CREATE TRIGGER TR_UPD_Lake_Shape ON Lake_Shape
 FOR  INSERT, UPDATE 
AS 
SET NOCOUNT ON
BEGIN
    WITH cte AS
    (
        SELECT l.Lake_Shape_id, l.lake_id, geometry::STGeomFromWKB(l.Lake_Shape_shape.STAsBinary(), l.Lake_Shape_shape.STSrid).STEnvelope() AS box 
            FROM Lake_Shape l JOIN inserted i ON l.lake_id = i.lake_id AND l.Lake_Shape_id = i.Lake_Shape_id WHERE l.Lake_Shape_shape IS NOt NULL
    )
    UPDATE t SET t.Lake_Shape_idx = box, t.Lake_Shape_hash = COALESCE(t.Lake_Shape_hash,  CAST(HashBytes('MD5', t.Lake_Shape_shape.ToString()) AS bigint))
        FROM Lake_Shape t JOIN cte ON cte.lake_id = t.lake_id AND cte.Lake_Shape_id = t.Lake_Shape_id
END
GO
/*
update Lake_Shape set Lake_Shape_hash = CAST(HashBytes('MD5', Lake_Shape_shape.ToString()) AS bigint)

DECLARE @g geography;  
SET @g = geography::STGeomFromText('LINESTRING(-122.360 47.656, -122.343 47.656)', 4326);  
SELECT @g.ToString();  
*/
------------------------------------------------------------------------------
CREATE TABLE news
(
    news_id				uniqueidentifier   NOT NULL,
    id					bigint not null identity(1,2),
    news_title			sysname,
    news_author			sysname,
    news_author_link	nvarchar(1024),
    news_source			nvarchar(255),
    news_source_link	nvarchar(1024),
    news_publish		bit NOT NULL DEFAULT(0),
    news_video_link		nvarchar(255),

    news_photo0			varbinary(max),
    news_photo_author0	nvarchar(64),
    news_photo_alt0	    nvarchar(128),
    news_paragraph0		nvarchar(max),

    news_photo1			varbinary(max),
    news_photo_author1	nvarchar(64),
    news_photo_alt1	    nvarchar(128),
    news_paragraph1		nvarchar(max),

    news_photo2			varbinary(max),
    news_photo_author2	nvarchar(64),
    news_photo_alt2	    nvarchar(128),
    news_paragraph2		nvarchar(max),

    lake_id				uniqueidentifier,	-- name of mentioned lake
    fish1_id			uniqueidentifier,	-- name of mentioned fish 1
    fish2_id			uniqueidentifier,	-- name of mentioned fish 2
    fish3_id			uniqueidentifier,	-- name of mentioned fish 3
    country				char(2),			-- origin of news
    news_stamp			datetime2 NOT NULL,
    stamp				datetime2 NOT NULL,
    CONSTRAINT PK_news PRIMARY KEY CLUSTERED (news_id)
)
ALTER TABLE news add constraint df_news_Id default NEWSEQUENTIALID() for news_id
GO  
ALTER TABLE news add constraint DF_news_stamp default getutcdate() for stamp
GO
ALTER TABLE news add constraint DF_news_juststamp default getutcdate() for news_stamp
GO
ALTER TABLE news ADD CONSTRAINT FK_news_lake FOREIGN KEY (lake_id) REFERENCES lake(lake_id) ON DELETE CASCADE ON UPDATE CASCADE;
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_news_title ON news( news_title ) 
GO
CREATE NONCLUSTERED INDEX idx_news_lake ON news (lake_id)
GO
ALTER TABLE news ADD CONSTRAINT FK_news_fish1 FOREIGN KEY (fish1_id) REFERENCES fish(fish_id) ON DELETE CASCADE ON UPDATE CASCADE;
GO
CREATE NONCLUSTERED INDEX idx_news_fish1 ON news (fish1_id)
GO
CREATE NONCLUSTERED INDEX IDX_news_country ON news (news_publish, country);
GO
CREATE NONCLUSTERED INDEX IDX_news_stamp ON news (news_stamp);
GO
CREATE NONCLUSTERED INDEX IDX_news_time ON news (stamp);
GO
CREATE NONCLUSTERED INDEX IDX_news_country2 ON news (country);
GO
CREATE NONCLUSTERED INDEX IDX_news_publish ON news (news_publish)
INCLUDE (news_title,news_source,news_photo0,news_stamp,id,country)
GO

CREATE TRIGGER TR_ins_news ON news
 FOR INSERT
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    
	DECLARE @lake_id uniqueidentifier, @fish1_id uniqueidentifier, @fish2_id uniqueidentifier, @fish3_id uniqueidentifier, @link nvarchar(1024)

	SELECT TOP 1 @lake_id = lake_id, @fish1_id = fish1_id, @fish2_id = fish2_id, @fish3_id = fish3_id, @link = news_source_link
		FROM INSERTED

	IF @lake_id IS NOT NULL AND (@fish1_id IS NOT NULL OR @fish2_id IS NOT NULL OR @fish3_id IS NOT NULL)
	BEGIN
		INSERT INTO lake_fish (lake_id, fish_id, created, probability, link )
			SELECT @lake_id, fish_id, getdate(), 2, @link
				FROM (VALUES (@fish1_id), (@fish2_id), (@fish3_id) )x(fish_id) 
				WHERE fish_id IS NOT NULL AND NOT EXISTS (SELECT * FROM lake_fish a WHERE a.lake_id = @lake_id AND a.fish_id = x.fish_id)
	END
END
GO
------------------------------------------------------------------------------
-- each object from lake has mouth record with side=32 and source record with side=16 and Main_Lake_id=Lake_id
-- ion insert into lake trigger insert pare od records into Tributaries
-- each entry in lake always has 2 entries for Tributaries: 16 and 32
-- entry for Tributaries with 
CREATE TABLE Tributaries
(
    id              int not null identity,
    Main_Lake_id    uniqueidentifier   NOT NULL,  -- main string
    Lake_id         uniqueidentifier   NOT NULL,  -- Tributarie's stream
    lat             float,
    lon             float,
    Country         char(2) NULL,
    State           char(2) NULL,
    county          nvarchar(64) NULL,                    -- source county
    city            nvarchar(64) NULL,                    -- source Kitchener
    elevation       int,                                -- m for lakes
    pic             varbinary(max),
    location        nvarchar(max),
    descript        nvarchar(max),
    district        nvarchar(128),                      -- source district
    municipality    nvarchar(128),
    region          nvarchar(128),
    zone            int,
    side            int NOT NULL,                      -- 1 - link, 2 - lake Throw, 4 - Inflow Lake, 8 - outflow Lake, 16 - source, 32 - mouth, 64 - joined
	coast           varchar(1),                       -- L - left, R- right
    Tributaries_stamp DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT PK_Tributaries PRIMARY KEY CLUSTERED (id)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UK_Tributaries_Source ON Tributaries(Main_Lake_id, side)   WHERE side = 16
GO
CREATE UNIQUE NONCLUSTERED INDEX UK_Tributaries_Mouth ON Tributaries(Main_Lake_id, side)    WHERE side = 32
GO

CREATE INDEX IDX_Tributaries_lakes ON Tributaries(lake_id) INCLUDE (main_lake_id, side, coast) 
GO
CREATE INDEX IDX_Tributaries_DEF ON Tributaries(side, lat, lon) INCLUDE (main_lake_id, district, region, municipality, county, city, location);
GO
CREATE NONCLUSTERED INDEX IDX_Tributaries_XY ON dbo.Tributaries (lat, lon) INCLUDE (Lake_id, main_lake_id);
GO
CREATE INDEX IDX_Tributaries_ML ON Tributaries(side) INCLUDE (main_lake_id, lake_id, lat, lon, country, state, county, city, location, district, zone, municipality, region);
GO
-- update t set t.location = l.location from lake l join Tributaries t on l.lake_id=t.lake_id and t.Main_Lake_id=l.lake_id and side=16
ALTER TABLE Tributaries ADD CONSTRAINT FK_Tributaries_lake FOREIGN KEY(Main_Lake_id) REFERENCES lake( Lake_id );
GO
ALTER TABLE Tributaries ADD CONSTRAINT FK_Tributaries_lake2 FOREIGN KEY(Lake_id) REFERENCES lake( Lake_id );
GO
CREATE NONCLUSTERED INDEX IDX_Tributaries_p4f ON [dbo].[Tributaries] ([Main_Lake_id]) INCLUDE ([Lake_id],[lat],[lon],[side],[Tributaries_stamp],[Country],[State],[county],[city],[elevation],[pic],[location],[descript],[district],[zone],[municipality],[region],[coast])
GO

if object_id('TR_Lake_INS') is not null drop TRIGGER TR_Lake_INS
GO
-- insert default description of source (16) and mouth (32) parts of rives. for now fake one if not exists real one
CREATE TRIGGER TR_Lake_INS ON Lake FOR INSERT NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    INSERT INTO Tributaries (Main_Lake_id, lake_id, side ) 
            SELECT lake_id, lake_id, 16  FROM INSERTED UNION ALL SELECT lake_id, lake_id, 32  FROM INSERTED
END
GO
-----------------------------------------------------------------------------------------------------------------------
if object_id('TR_UPD_Tributaries') is not null drop TRIGGER TR_UPD_Tributaries
GO
-----------------------------------------------------------------------------------------------------------------------
CREATE TRIGGER dbo.TR_UPD_Tributaries ON dbo.Tributaries
AFTER UPDATE
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    UPDATE t set t.country = CASE WHEN t.state in ('ON', 'QC','BC','AB','MB','SK','NS','NB','NL','PE','NT','YT','NU') THEN 'CA' ELSE 'US' END
        FROM Tributaries t JOIN INSERTED i ON t.Lake_id = i.Lake_id AND t.Main_Lake_id = i.Main_Lake_id
        WHERE t.country IS NULL AND t.state IS NOT NULL

    UPDATE l SET source = t.Lake_id, l.stamp = getdate() FROM lake l JOIN INSERTED t ON l.lake_id = t.Main_Lake_id AND l.lake_id <> t.Lake_id AND t.side = 16
    UPDATE l SET mouth  = t.Lake_id, l.stamp = getdate() FROM lake l JOIN INSERTED t ON l.lake_id = t.Main_Lake_id AND l.lake_id <> t.Lake_id AND t.side = 32
    -- set the same elevation for lake/pond, .. for mouth/source points
    IF UPDATE (elevation)   -- set for lakes the same elevation for source/mouth
    BEGIN
        UPDATE t SET t.elevation = COALESCE(m.elevation, t.elevation) 
            FROM Tributaries t JOIN Tributaries m ON t.Main_Lake_id = m.Main_Lake_id AND m.side <> t.side
                JOIN INSERTED i ON m.id = i.id 
            WHERE EXISTS (SELECT * FROM lake l WHERE l.Lake_id = t.Main_Lake_id AND l.locType IN (1,8,8192))
                AND m.side IN (16,32) AND t.side IN (16,32)
    END
    -- if changed lake the inforce to change linked points
    UPDATE rv SET rv.zone = (CASE WHEN lk.country=rv.Country AND lk.State = rv.State THEN lk.zone END), rv.elevation = lk.elevation
        FROM Tributaries lk JOIN Tributaries rv ON lk.main_lake_id = rv.lake_id AND rv.lake_id <> rv.main_lake_id
            JOIN INSERTED i ON i.id = lk.id
            JOIN Lake l ON l.lake_id = lk.main_lake_id
            WHERE l.locType IN (1,8,8192)
END
GO
-----------------------------------------------------------------------------------------------------------------------
if object_id('TR_INS_Tributaries') is not null drop TRIGGER TR_INS_Tributaries
GO
-----------------------------------------------------------------------------------------------------------------------
CREATE TRIGGER dbo.TR_INS_Tributaries ON dbo.Tributaries
AFTER INSERT
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
	IF 1 = (SELECT CAST(COUNT(*) AS INT) FROM INSERTED )
	BEGIN
		IF EXISTS (SELECT * FROM Tributaries t JOIN INSERTED n ON n.id=t.id WHERE n.side = 2 )
		BEGIN
		   UPDATE t SET t.Lake_id = n.main_lake_id FROM INSERTED n JOIN Tributaries t ON n.lake_id=t.Main_Lake_id AND t.Main_Lake_id = t.Lake_id AND t.side = 16
		   UPDATE t SET t.Lake_id = n.main_lake_id FROM INSERTED n JOIN Tributaries t ON n.lake_id=t.Main_Lake_id AND t.Main_Lake_id = t.Lake_id AND t.side = 32
		END
	END
END
GO
-----------------------------------------------------------------------------------------------------------------------
CREATE TABLE zone_regulations
(
    regulations_id          uniqueidentifier NOT NULL,
    zone_id                 int              NOT NULL,  
    Lake_id                 uniqueidentifier     NULL,
    fish_id                 uniqueidentifier     NULL,
    regulations_date_start  DATE,
    regulations_start       varchar(64),      -- non standart date
    regulations_date_end    DATE,
    regulations_end         varchar(64),      -- non standart date
    regulations_sport_text  nvarchar(255), 
    regulations_consr_text  nvarchar(255), 
    regulations_code        int,              -- 1 - Fish sanctuary - no fishing, 2 -Live fish may not be used as bait or possessed for use as bait. 
    regulations_link        nvarchar(255),
    regulations_stamp       DATETIME2,
    regulations_part        nvarchar(max),
    CONSTRAINT PK_zone_regulations PRIMARY KEY CLUSTERED (regulations_id),
    CONSTRAINT FK_zone_regulations FOREIGN KEY(fish_id) REFERENCES fish( fish_id )
 );
GO

ALTER TABLE zone_regulations add constraint df_zone_regulations default NEWSEQUENTIALID() for regulations_id
GO
ALTER TABLE zone_regulations add constraint df_zone_regulations_stamp default getutcdate() for regulations_stamp
GO
 ------------------------------------------------------------------------------
  -- http://files.ontario.ca/environment-and-energy/fishing/mnr_e001331.pdf
--  drop function fn_river_view_regulations
--  drop function fn_GetLakeRegulations
--  drop VIEW vw_regulations
-- select * FROM regulations  
CREATE TABLE regulations  
(
    id                      int NOT NULL IDENTITY(1,1),
    regulations_id          uniqueidentifier NOT NULL,
    regulations_part        nvarchar(255),                  -- comment for this regulation
    state                   char(2) NOT NULL,               -- ON - Ontario    
    zone_id                 int     NULL,  
    Lake_id                 uniqueidentifier,
    fish_id                 uniqueidentifier NOT NULL,
    chain                   uniqueidentifier, -- if regulation combain several fishes : Walleye or Sauger combined
    regulations_date_start  DATE,
    regulations_start       varchar(64),      -- non standart date
    regulations_date_end    DATE,
    regulations_end         varchar(64),      -- non standart date
    regulations_sport       int,              -- NULL - N/A
    regulations_sport_text  nvarchar(255), 
    regulations_consr       int,              -- NULL - N/A
    regulations_consr_text  nvarchar(255), 
    regulations_code        int,              -- 1 - Fish sanctuary - no fishing, 2 -Live fish may not be used as bait or possessed for use as bait. 
    regulations_link        nvarchar(255),
    regulations_stamp       DATETIME2,
    regulations_text        nvarchar(max), 
    CONSTRAINT PK_Regulations PRIMARY KEY CLUSTERED (regulations_id),
    CONSTRAINT FK_regulations_lake FOREIGN KEY(Lake_id) REFERENCES lake( Lake_id ),
    CONSTRAINT FK_regulations_fish FOREIGN KEY(fish_id) REFERENCES fish( fish_id ),
    CONSTRAINT UK_regulations UNIQUE (state, zone_id, Lake_id, fish_id)
);
GO

ALTER TABLE regulations add constraint df_regulations_id default NEWSEQUENTIALID() for regulations_id
GO
ALTER TABLE regulations add constraint df_regulations_stamp default getutcdate() for regulations_stamp
GO
ALTER TABLE regulations ADD CONSTRAINT CH_regulations CHECK (fish_id <> chain)
GO

--------------------------------------------------------------------------------------------
if object_id('TR_regulations') is not null drop TRIGGER TR_regulations
GO

CREATE TRIGGER TR_regulations ON regulations
 FOR INSERT
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN TRY

    INSERT INTO lake_fish (lake_id, fish_id, created, link, probability, probability_source_type)
        SELECT lake_id, fish_id, getdate(), regulations_link, 0, 0 FROM INSERTED i 
            WHERE NOT EXISTS (SELECT * FROM lake_fish l WHERE l.lake_Id = i.lake_Id AND l.fish_id = i.fish_id)
                AND lake_id IS NOT NULL AND fish_id IS NOT NULL 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()   AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , 'TR_regulations' AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO    
------------------------------------------------------------------------------
------------------------------------------------------------------------------
CREATE TABLE fish_record
(
    fish_id     uniqueidentifier NOT NULL,
    lake_id     uniqueidentifier NOT NULL,
    stamp       date not null,
    angler      nvarchar(64),
    weight      float,              -- lb
    length      float,              -- in
    Girth       float,              -- in
    lure        varchar(64),
    link        nvarchar(max),
    CONSTRAINT  FK_fish_rec_fish FOREIGN KEY ( fish_Id ) REFERENCES fish(fish_id) ON DELETE CASCADE,
    CONSTRAINT  FK_fish_rec_lake FOREIGN KEY ( lake_id ) REFERENCES lake(lake_id) ON DELETE CASCADE
);
GO
ALTER TABLE fish_record ADD CONSTRAINT UK_fish_record UNIQUE NONCLUSTERED ( fish_id, lake_id, stamp );
GO

-----------------------------------------------------------------------------

-- has reletations between list of species and lakes
CREATE TABLE lake_fish
(
    lake_Id    uniqueidentifier NOT NULL,
    fish_Id    uniqueidentifier NOT NULL,
    created    datetime2 NOT NULL,
    link       nvarchar(max),                  --  proof link to source
    probability tinyint NOT NULL default(0),   -- 0 - science documents (high priority), 2- site owner, 4 - paid fishers, 8 - unknown fishers
           --   32 - pushed from other source of the same type, 
           --   64 - pushed from other source of the different type
    probability_source_type tinyint NOT NULL DEFAULT ((0)),
    spawn        int,
    sid          int,
    tributaries  int,
    forbidden    int,
    Distribution char(1) NULL DEFAULT ('N'),
    note         nvarchar(1024),
	status       tinyint,                      -- 1 - at risk
	method       nvarchar(max),                -- how to fish
    stamp        datetime2        CONSTRAINT DF_lake_fish_stamp DEFAULT(getdate())
);
GO

ALTER TABLE lake_fish ADD PRIMARY KEY (lake_Id, fish_Id, probability);
GO
ALTER TABLE lake_fish add constraint DF_lake_fish_created default getutcdate() for created
GO
CREATE NONCLUSTERED INDEX IDX_lake_fish_p4f ON [dbo].[lake_fish] ([fish_id]) INCLUDE ([created],[link],[probability_source_type],[spawn],[sid],[tributaries],[forbidden],[Distribution],[note],[status],[method],[stamp])
GO

CREATE TRIGGER TR_insLakes_Fish ON lake_fish
 FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    -- single row 
  DECLARE @tbl TABLE (station_Id uniqueidentifier, fish_ID uniqueidentifier, state char(2), country char(2) )
  INSERT INTO @tbl SELECT DISTINCT w.id, i.fish_id, w.state, w.country
    from [dbo].[WaterStation] w, INSERTED i WHERE w.lakeId = i.lake_Id

  IF EXISTS (SELECT * FROM @tbl)
  BEGIN
    INSERT INTO dbo.fish_location( station_Id, fish_Id, today, stamp )
      SELECT station_Id, fish_Id, 0, GETUTCDATE() FROM @tbl t 
        WHERE NOT EXISTS (SELECT * FROM fish_location f WHERE f.station_Id = t.station_Id AND f.fish_Id=t.fish_ID)
  END

  UPDATE l SET [IsFish] = 1 FROM lake l JOIN INSERTED i ON l.lake_id=i.lake_id
END
GO
-------------------------------------------------------------------------------------------------------

-- Created by GitHub Copilot in SSMS - review carefully before executing
CREATE TABLE [dbo].[SessionHandler]
(
    [id]            UNIQUEIDENTIFIER NOT NULL,
    [ip4]           VARCHAR(45) NULL,
    [ip6]           VARCHAR(45) NULL,
    [startSess]     DATETIME NOT NULL,
    [userAgent]     VARCHAR(255) NOT NULL,
    [host]          VARCHAR(255) NOT NULL,
    [startPage]     VARCHAR(255) NULL,
    [userId]        UNIQUEIDENTIFIER NULL,
    [sid]           BIGINT IDENTITY(1,2) NOT NULL,
    [counterPage]   INT NOT NULL,
    [baned]         BIT NOT NULL,
    [activityDate]  AS CONVERT([date], [startSess]) PERSISTED,

    CONSTRAINT [PK_SessionHandler]
        PRIMARY KEY CLUSTERED ([id] ASC),

    CONSTRAINT [UQ_SessionHandler_sid]
        UNIQUE NONCLUSTERED ([sid] ASC),

    CONSTRAINT [CK_SessionHandler_counterPage]
        CHECK ([counterPage] >= 0),

    CONSTRAINT [CK_SessionHandler_IpRequired]
        CHECK (ISNULL(NULLIF(LTRIM(RTRIM([ip4])), ''), NULLIF(LTRIM(RTRIM([ip6])), '')) IS NOT NULL)
);
GO
ALTER TABLE [dbo].[SessionHandler] ADD CONSTRAINT [DF_SessionHandler_Id] DEFAULT (NEWID()) FOR [id];
GO
ALTER TABLE [dbo].[SessionHandler] ADD CONSTRAINT [DF_SessionHandler_startSess] DEFAULT (GETUTCDATE()) FOR [startSess];
GO
ALTER TABLE [dbo].[SessionHandler] ADD CONSTRAINT [DF_SessionHandler_counterPage] DEFAULT ((0)) FOR [counterPage];
GO
ALTER TABLE [dbo].[SessionHandler] ADD CONSTRAINT [DF_SessionHandler_baned] DEFAULT ((0)) FOR [baned];
GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_SessionHandler_ActivityDate_Ip4]
ON [dbo].[SessionHandler] ([activityDate], [ip4])
WHERE [ip4] IS NOT NULL AND [ip4] <> '';
GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_SessionHandler_ActivityDate_Ip6]
ON [dbo].[SessionHandler] ([activityDate], [ip6])
WHERE [ip6] IS NOT NULL AND [ip6] <> '';
GO

CREATE NONCLUSTERED INDEX [IX_SessionHandler_Baned_Ip4]
ON [dbo].[SessionHandler] ([baned], [ip4])
INCLUDE ([activityDate], [counterPage], [host], [startPage], [userAgent], [startSess])
WHERE [ip4] IS NOT NULL AND [ip4] <> '';
GO

CREATE NONCLUSTERED INDEX [IX_SessionHandler_Baned_Ip6]
ON [dbo].[SessionHandler] ([baned], [ip6])
INCLUDE ([activityDate], [counterPage], [host], [startPage], [userAgent], [startSess])
WHERE [ip6] IS NOT NULL AND [ip6] <> '';
GO

CREATE NONCLUSTERED INDEX [IX_SessionHandler_Host_ActivityDate_Ip4]
ON [dbo].[SessionHandler] ([host], [activityDate], [baned], [ip4])
INCLUDE ([counterPage], [startPage], [userAgent], [startSess])
WHERE [ip4] IS NOT NULL AND [ip4] <> '';
GO

CREATE NONCLUSTERED INDEX [IX_SessionHandler_Host_ActivityDate_Ip6]
ON [dbo].[SessionHandler] ([host], [activityDate], [baned], [ip6])
INCLUDE ([counterPage], [startPage], [userAgent], [startSess])
WHERE [ip6] IS NOT NULL AND [ip6] <> '';
GO

-- update GlobalConfig table for number of visiters
CREATE TRIGGER trg_UpdateGlobalConfig
ON SessionHandler
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @currentDay DATE = CAST(GETDATE() AS DATE);
    
    -- Only update if we have NEW unique IP addresses for today
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.ip4 IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM SessionHandler sh
            WHERE sh.ip4 = i.ip4
            AND CAST(sh.startSess AS DATE) = @currentDay
            AND sh.id <> i.id  -- Exclude the just-inserted row
        )
    )
    BEGIN
        -- Update the global configuration counter
        UPDATE global_configuration
        SET config_value = (
            SELECT 500000 + SUM(UniqueIPCount)
            FROM (
                SELECT COUNT(DISTINCT ip4) AS UniqueIPCount
                FROM SessionHandler
                WHERE ip4 IS NOT NULL
                GROUP BY CAST(startSess AS DATE)
            ) t
        )
        WHERE config_attribute = 'counter';
    END
END;
GO

-------------------------------------------------------------------------------------------------------
CREATE TABLE Spot
(
    spot_lat  float NULL,
    spot_lon  float NULL,
    lake_Id   uniqueidentifier NOT NULL DEFAULT ('00000000-0000-0000-0000-000000000000'),
    spot_id uniqueidentifier NOT NULL DEFAULT (NEWSEQUENTIALID()),
    spot_sid  int not null identity(1,1),
    spot_created datetime2 NOT NULL DEFAULT (getdate()),
    spot_link nvarchar(255),
    PRIMARY KEY CLUSTERED (    spot_id ASC)
) 
GO
-------------------------------------------------------------------------------------------------------
--alter TABLE States add park_rules nvarchar(512)
CREATE TABLE States
(
   state            char(2) not null,
   country          char(2) not null,
   name             nvarchar(64),
   shift            int     not null default(0),
   lat              float,
   lon              float,
   rules            nvarchar(512),
   park_rules       nvarchar(512),
   resident_fee     nvarchar(128),
   non_resident_fee nvarchar(128)
)
GO
ALTER TABLE States ADD CONSTRAINT PK_States PRIMARY KEY CLUSTERED (state, country)
GO
-------------------------------------------------------------------------------------------------------
CREATE TABLE Users
(
    id         uniqueidentifier NOT NULL,
    UsersId    bigint not null identity(1,128),  -- second parametr - node id
    userName   varchar(64) NOT NULL,
    psw        binary(16) NOT NULL,
    titul      nvarchar(32) NULL,
    firstName  nvarchar(64) NOT NULL,
    lastName   nvarchar(64) NOT NULL,
    email      varchar(128) NOT NULL,
    stamp      datetime2 NOT NULL,
    lastVisit  datetime2 NOT NULL,
    postal     varchar(16) NULL,
    subs       BIT,
    question   nvarchar(64) NOT NULL,
    answer     binary(16) NOT NULL,
    cell       bigint,
    access     int NOT NULL,               -- 255 superAdmin
    suspended  BIT,
    ipaddr     varchar(32) NULL,
    addr       varchar(255) NULL,
    agent      varchar(128) NULL,
    host       varchar(1024) NULL,
    country    char(2) NULL
) 
GO

ALTER TABLE Users ADD CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (id) 
ALTER TABLE Users add constraint df_USer_Id default NEWSEQUENTIALID() for [id]
ALTER TABLE Users add constraint df_USer_stamp default getutcdate() for stamp
ALTER TABLE Users add constraint df_USer_lastVisit default getutcdate() for lastVisit
ALTER TABLE Users add constraint df_USer_access default 0 for access;
CREATE UNIQUE NONCLUSTERED INDEX UK_Users_Email ON Users(email);
ALTER TABLE users ADD CONSTRAINT CH_users_email CHECK ( datalength(email) >= 6 and email not like '%@%@%' and email not like '%[^a-zA-Z0-9_.-@]%');
ALTER TABLE users ADD CONSTRAINT CH_users_userName CHECK (DATALENGTH(userName) >= 3);
ALTER TABLE users ADD CONSTRAINT CH_users_psw CHECK (DATALENGTH(psw) >= 6);
GO
---------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO Users (userName, psw, titul, firstName, lastName, email, postal, subs, question, answer, cell, access) 
          VALUES  ('Lepsik', HashBytes('MD5', 'vertex*solt'), 'Mr.', 'Lepsik'
                   , 'Baralgeen', 'LBaralgeen@gmail.com', 'N2M5L4', 1, 'preved', HashBytes('MD5', 'medved+zuker'), 12266005162, 255)
GO
-------------------------------------------------------------------------------------------------------
CREATE TABLE USPost
(
    zip         int NOT NULL,
    place       varchar(64),
    lat         float not null default(0.0),
    lon         float not null default(0.0),
    county      varchar(32),
    [state]     varchar(16)
);
GO
ALTER TABLE USPost ADD CONSTRAINT PK_USPost PRIMARY KEY CLUSTERED (zip ASC) ON [PRIMARY]    
GO
------------------------------keep last 7 days water state--------------------------------
CREATE TABLE dbo.WaterData
(
    mli            varchar(64) NOT NULL,
    stamp          smalldatetime NOT NULL,    -- actual data reading on  site mli
    temperature    tinyint,             -- [0..127] C
    discharge      float,               -- [(m3/s] cms
    turbidity      smallint,            -- [0.999] ppm
    oxygen         float,               -- [mg/L] ppm
    ph             tinyint,             -- [0..10] NN -- value in database devided by 10 from real value (must by mulipled to 10 on viewing)
    elevation      float,               -- [m]
    precipitation  smallint,            -- [mm]
    wind           tinyint,             -- [m/s]
    winddir        smallint,
    humidity       tinyint,             -- [%]
    air            tinyint,             -- [-63..+63] C  -- value in database half from real value (must by mulipled to 2 on viewing)
    velocity       tinyint,             -- [m/s]
    pressure       smallint,            -- [Torr]  ~760mm
	Phycocyanins   float,
	Chlorophylls   float,
	Cyanobacteria  float,
	Orthophosphate float,
	nitrate        float,
	chloride       float,
	phycoerythrin  float,
	salinity       float,
    id             bigint IDENTITY(1,1) NOT NULL primary key,
    --sid            bigint NOT NULL CONSTRAINT df_WaterData_sid DEFAULT(0)
);
GO

ALTER TABLE WaterData add constraint df_WaterData_DT default getdate() for stamp;
GO

CREATE INDEX IDX_WaterData_dt ON dbo.WaterData(stamp);
GO

CREATE UNIQUE NONCLUSTERED INDEX UK_WaterData_MLI_stamp ON dbo.WaterData(MLI, stamp);
GO
-- used in [spTotalUpdateProbability]  update fish probabilty based on water temperature
CREATE NONCLUSTERED INDEX IDX_TM_WaterData ON [dbo].[WaterData] ([temperature]) INCLUDE ([mli])
GO
CREATE NONCLUSTERED INDEX IDX_PH_WaterData ON [dbo].[WaterData] ([ph]) INCLUDE ([mli])
GO
--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------

if object_id('TR_insWaterData') is not null drop TRIGGER dbo.TR_insWaterData
GO
--------------------------------------------------------------------------------------------

CREATE TRIGGER dbo.TR_insWaterData ON dbo.WaterData 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN    -- single row 

WITH cte AS
(
    SELECT i.mli, i.stamp, temperature
		, CASE WHEN CAST(discharge AS INT) <> -999 THEN discharge ELSE NULL END AS discharge
		, turbidity, oxygen, ph, i.elevation, w.sid 
		FROM INSERTED i
        JOIN dbo.WaterStation w ON w.mli=i.mli
        WHERE i.id IN ( SELECT MAX(id) FROM INSERTED GROUP BY mli )
)
    Merge Into dbo.CurrentWaterState As trg Using cte As src
          On src.mli = trg.mli
    When Matched Then
    Update Set
          trg.temperature = ISNULL(src.temperature, trg.temperature)
		, trg.stamp       = ISNULL(src.stamp,       trg.stamp) 
        , trg.discharge   = ISNULL(src.discharge,   trg.discharge)
        , trg.turbidity   = ISNULL(src.turbidity,   trg.turbidity)
        , trg.oxygen      = ISNULL(src.oxygen,      trg.oxygen)
        , trg.ph          = ISNULL(CAST(src.ph AS float) / 10.0, trg.ph)
        , trg.elevation   = ISNULL(src.elevation,   trg.elevation) 
        , trg.sid         = src.sid 
    When Not Matched Then
    Insert (mli, stamp, temperature, discharge, turbidity, oxygen, ph, elevation) 
        Values (src.mli, src.stamp, src.temperature, src.discharge, src.turbidity, src.oxygen, CAST(src.ph AS float) / 10.0, src.elevation);
END
GO
--------------------------------------------------------------------------------------------
/*
    Table: WaterStation

    Description:
    Stores metadata for hydrometric and water-related monitoring locations used by the system
    to ingest, track, and process station-based environmental data.

    Each row represents a single external water station or location identified by MLI and
    internal system identifiers. The table contains geographic coordinates, source/provider
    metadata, location classification, processing state, weather snapshot fields, and mapping
    fields used to associate the station with lakes, cities, and upstream source records.
*/
--------------------------------------------------------------------------------------------
CREATE TABLE WaterStation
(
    MLI           varchar(64) NOT NULL,       -- External station identifier used by the source provider.
    id            uniqueidentifier default NEWSEQUENTIALID() NOT NULL ,
    state         char(2),                    -- Two-character province/state/region code.
    lat           float NOT NULL,             -- Latitude of the station in decimal degrees.
    lon           float NOT NULL,             -- Longitude of the station in decimal degrees
    tz            int,                        -- Time zone offset or internal time zone code for the station location.  
    country       char(3) NOT NULL,           -- Three-character country code.   CA, US
    locDesc       varchar(max) NOT NULL,      -- Full textual description of the station location.
    processed     datetime2,                  --  Timestamp of the last successful processing of this station by the ingestion pipeline
    locType       int NOT NULL DEFAULT(0),     --  1 - lake, 2 - river,  4 - stream, 8 - pond, 16 - marsh, 32 - backwater, 64 - creek
                                               --  128 - canal, 256 - Estuary, 512 - shore, 1024 - drain, 2048 - ditch, 4096 = Wetland,  8192 - Reservoir 
    condition     varchar(255),                -- Current weather condition text associated with the station location.
    wheatherStamp datetime2,                   -- last time when a wheather was saved   
    agency        sysname default(''),         -- Source agency or provider name responsible for the station data.
    county        sysname,                     -- County or regional administrative area for the station.
    locName       varchar(255) NOT NULL,       -- Short display name of the water location or station.
    oldId         int,                         -- Legacy numeric identifier taken from the original source system.
    sid           int not null,                -- Internal or source-specific station numeric identifier.
    passed        int,                         -- Processing/status counter or internal pass marker used by import logic.
    updData       datetime2,                   -- last time when a data was updated   
    lakeId        uniqueidentifier,            -- Internal unique identifier of the related lake entity, if applicable.     
    lakeName      nvarchar(64) NOT NULL,       -- Name of the associated lake or parent water body. 
    elevation     int,                         -- Elevation of the station location, typically above sea level.
    stamp         datetime2 not null CONSTRAINT df_WaterStation_stamp DEFAULT GETUTCDATE(),  -- Row creation timestamp in UTC.
    city          nvarchar(128),
    road          nvarchar(255),
    city_id       int,
	pass          bit default(1),
    supported     bit not null default(1)       -- not supprted by https://dd.weather.gc.ca or https://waterservices.usgs.gov. WaterData service does not process it if false
) 
GO

--CREATE NONCLUSTERED INDEX [idx_WaterStation_id] ON WaterStation (id )
ALTER TABLE WaterStation ADD CONSTRAINT PK_WaterStationId PRIMARY KEY CLUSTERED (id);
    
CREATE UNIQUE NONCLUSTERED INDEX UK_WaterStation ON WaterStation(mli)    
CREATE NONCLUSTERED INDEX [idx_WaterStation_lat] ON WaterStation (lat ASC ) ON [PRIMARY]
CREATE NONCLUSTERED INDEX [idx_WaterStation_lon] ON WaterStation (lon ASC ) ON [PRIMARY]
CREATE NONCLUSTERED INDEX [idx_WaterStation_state] ON WaterStation (state) ON [PRIMARY]
CREATE NONCLUSTERED INDEX [idx_WaterStation_city] ON WaterStation (city) ON [PRIMARY]
CREATE NONCLUSTERED INDEX [idx_WaterStation_sid] ON WaterStation (sid) ON [PRIMARY]
CREATE NONCLUSTERED INDEX [idx_WaterStation_mli] ON WaterStation (mli) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX idx_WaterStation_cll ON WaterStation (country,lat,lon) INCLUDE (id)
GO
-- select top 1 * from WaterStation
CREATE NONCLUSTERED INDEX idx_WaterStation_latlon ON [dbo].[WaterStation] ([lat],[lon]) INCLUDE ([lakeId])
GO

ALTER TABLE dbo.WaterStation  ADD CONSTRAINT FK_WaterStation_Lake FOREIGN KEY(lakeId) REFERENCES dbo.Lake (lake_id)
GO
-- select lakeId, lakename from WaterStation where lakeId not in (select lake_id from lake)

-- select mli, lat, lon from WaterStation where lakeId is null

-- update WaterStation set lakeId='0c53c2ab-849c-20c3-7b99-cbf904702ab4', lakename = 'Venison Creek' where mli = '02GC038'

-- delete from WaterStation where mli = '02GH016'

CREATE TRIGGER trg_WaterStation_AI_ows_meteo
ON dbo.WaterStation
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ows_meteo (
        WaterStation_id,
        mli,
        country,
        state,
        lat,
        lon,
        stamp,
        type
    )
    SELECT
        i.id,
        i.mli,
        i.country,
        i.state,
        i.lat,
        i.lon,
        GETDATE(),
        0                  -- default type (change if needed)
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.ows_meteo o
        WHERE o.WaterStation_id = i.id
    );
END;
GO

CREATE TRIGGER [dbo].[TR_WaterStation] ON [dbo].[WaterStation] 
FOR UPDATE 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @lakeid uniqueidentifier, @mli varchar(64) 

	IF UPDATE(lakeid)
	BEGIN
		SELECT TOP 1 @lakeid = lakeid, @mli=mli FROM INSERTED

		IF @mli IS NOT NULL AND @lakeid IS NOT NULL 
		BEGIN
			UPDATE w  SET lakeName =  l.lake_name, stamp = getdate()  
				FROM WaterStation w JOIN lake l ON l.lake_id = w.lakeId
			  WHERE w.mli = @mli AND l.lake_id = @lakeid 

			UPDATE l SET isWell =  1, l.stamp = getdate()  
				FROM WaterStation w JOIN lake l ON l.lake_id = w.lakeId
			  WHERE w.mli = @mli  AND l.lake_id = @lakeid

		END
	END
END
GO
-------------------------------------------------------------------------------------------------------
create table fish_location ( 
     station_Id uniqueidentifier not null
   , fish_Id    uniqueidentifier  not null
   , today      int default(0)                        -- current probability [0-100%]
   , stamp      datetime2   not null default getutcdate()
   , probability int default(0)                       -- original probabiliy from watershield 0 - means 100%
   , id         int
);
GO
ALTER TABLE fish_location ADD PRIMARY KEY (station_Id, fish_Id, stamp)
GO
CREATE NONCLUSTERED INDEX IDX_fish_location    ON fish_location (fish_Id) INCLUDE (station_Id)
GO
ALTER TABLE fish_location ADD CONSTRAINT FK_fish_location_fish FOREIGN KEY (fish_Id) 
   REFERENCES fish(fish_id) ON DELETE CASCADE ON UPDATE CASCADE;
GO
ALTER TABLE fish_location ADD CONSTRAINT FK_fish_location_station FOREIGN KEY (station_Id) 
   REFERENCES WaterStation(id) ON DELETE CASCADE ON UPDATE CASCADE;
GO
CREATE NONCLUSTERED INDEX [idx_fish_location_fish] ON fish_location (fish_Id ASC)  
GO
CREATE NONCLUSTERED INDEX [idx_fish_location_st] ON fish_location (station_Id ASC)  
GO
CREATE NONCLUSTERED INDEX [idx_fish_location_id] ON fish_location (id ASC) 

------------------------------------------------------------------------------
/******************************************************************************
Table: ows_meteo

Description:
Stores meteorological (weather) data associated with water monitoring stations.
The data is retrieved from external weather services (e.g., Weatherstack API)
and persisted in JSON format for further processing and analytics.

Example source:
http://api.weatherstack.com/current?access_key=...&query=<lat>,<lon>

Purpose:
- Maintain latest weather snapshot per WaterStation
- Support enrichment of hydrological / environmental data
- Enable downstream processing via stored procedures and triggers

Columns:
- WaterStation_id (PK, FK):
    Unique identifier of the water station (references WaterStation.id)

- mli (FK, unique):
    External station identifier (matches WaterStation.mli)

- country:
    ISO country code of the station location

- state:
    State/region code

- lat / lon:
    Geographic coordinates of the station

- type:
    Data source type
        1 = Weather Gateway (default)
        2 = Open weather source

- ows:
    Raw JSON document containing weather data returned by external API

- stamp (implicit):
    Timestamp of record creation/update (default = GETDATE())

Indexes:
- UK_ows_meteo_mli:
    Ensures one weather record per station (by mli)

Constraints:
- FK_ows_meteo_id:
    Enforces relation to WaterStation.id

- FK_ows_meteo_mli:
    Enforces relation to WaterStation.mli

Trigger:
- TR_ows_meteo (AFTER UPDATE):
    Invokes sp_ows_meteo stored procedure on update,
    passing updated JSON payload and station identifiers.
    Used for parsing, validation, or propagation of weather data.

Notes:
- Table is designed for semi-structured data (JSON in nvarchar(max))
- Intended for integration with external weather APIs
- Processing logic is delegated to sp_ows_meteo
******************************************************************************/

CREATE TABLE ows_meteo
(
      WaterStation_id     uniqueidentifier NOT NULL primary key
	, mli                 varchar(64)
    , country             char(2)
    , state               char(2)
    , lat				  float
    , lon				  float
    , type                int                       -- 1 - WG, 2-- Open
	, ows                 nvarchar(max)				-- JSON doc with weater
    , stamp               datetime
)
GO

CREATE UNIQUE NONCLUSTERED INDEX [UK_ows_meteo_mli] ON ows_meteo ( mli );
GO

ALTER TABLE [dbo].[ows_meteo] ADD  DEFAULT (getdate()) FOR [stamp]
GO

ALTER TABLE [dbo].[ows_meteo] ADD  DEFAULT (1) FOR [type]
GO

ALTER TABLE [dbo].[ows_meteo]  WITH CHECK ADD  CONSTRAINT [FK_ows_meteo_id] FOREIGN KEY([WaterStation_id])
REFERENCES [dbo].[WaterStation] ([id])
GO

ALTER TABLE [dbo].[ows_meteo] CHECK CONSTRAINT [FK_ows_meteo_id]
GO

ALTER TABLE [dbo].[ows_meteo]  WITH CHECK ADD  CONSTRAINT [FK_ows_meteo_mli] FOREIGN KEY([mli])
REFERENCES [dbo].[WaterStation] ([mli])
GO

ALTER TABLE [dbo].[ows_meteo] CHECK CONSTRAINT [FK_ows_meteo_mli]
GO

--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------
if object_id('TR_ows_meteo') is not null drop TRIGGER TR_ows_meteo
GO

CREATE TRIGGER TR_ows_meteo ON ows_meteo 
FOR UPDATE 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
	DECLARE @type int,  @json nvarchar(max), @mli varchar(64), @WaterStation_id uniqueidentifier
	SELECT TOP 1 @json = ows, @mli = mli, @WaterStation_id = WaterStation_id, @type = type FROM INSERTED
	IF @type = 1
      EXEC sp_ows_meteo      @json, @mli, @WaterStation_id
    ELSE IF @type = 2
      EXEC sp_ows_meteo_open @json, @mli, @WaterStation_id
END
GO

--------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------
CREATE TABLE weather_Forecast
(
    [link] [uniqueidentifier] NOT NULL,
    [tmHigh] [float] NOT NULL,
    [tmLow] [float] NOT NULL,
    [gpfDay] [float] NOT NULL,
    [gpfNight] [float] NOT NULL,
    [humidity] [float] NULL,
    wind_max_speed	float NULL,
    wind_degree		float NULL,
    wind_direction	varchar(8) NULL,
    [shortText] [varchar](64) NULL,
    [longText] [varchar](255) NULL,
    [icon] [varchar](255) NULL,
    [pop] [int] NULL,
    [dt] [date] NOT NULL,
    [tm]             time(7) NULL,
    mli              varchar(64) NOT NULL,
    city_id          int,
    tmDay            float,
    pressure         int,
    rain_today       int,
    air_temperature  int,
	weather_code     int
) ;
GO
ALTER TABLE dbo.weather_Forecast  ADD CONSTRAINT FK_weather_Forecast_stattion FOREIGN KEY([link]) REFERENCES dbo.WaterStation (id)
GO

CREATE UNIQUE NONCLUSTERED INDEX [UK_weatherForecast] ON [dbo].[weather_Forecast] ( link ,    dt , tm );
GO
-------------------------------------------------------------------------------------------------------------------------------
-- aspx saves excheptions here
CREATE TABLE LogException
(
    id          bigint NOT NULL identity(1, 128) primary key,
    msg         nvarchar(1024) NOT NULL,
    Users_Id    bigint,
    page_name   sysname NOT NULL,
    ip          varchar(64),
    email       sysname,
    stamp       datetime2 NOT NULL DEFAULT( GETUTCDATE() )
);
GO
------------------------------------------------------------------------------
CREATE TABLE fish_State
(
    fish_id  uniqueidentifier NOT NULL,
    fish_state_stamp datetime2 not null CONSTRAINT df_fish_staten_stamp DEFAULT GETUTCDATE(),
    PRIMARY KEY CLUSTERED (    fish_id )
) 
GO

ALTER TABLE dbo.fish_State  WITH CHECK ADD FOREIGN KEY(fish_id) REFERENCES dbo.fish (fish_id)
GO


------------------------------------------------------------------------------
---   INSERT INTO global_configuration (config_value, config_attribute ) VALUES ('2', 'node')
GO
---   INSERT INTO global_configuration (config_value, config_attribute ) VALUES ('0', 'source_node')
GO

INSERT INTO global_configuration (config_value, config_attribute ) VALUES ('010000', 'job_start')
GO

INSERT INTO global_configuration (config_value, config_attribute ) VALUES ('', 'job_executed')
GO
------------------------------------------------------------------------------
-- select * from global_configuration

CREATE TABLE merge_table
(
    table_name      sysname,
    operation       varchar(3),
    level           int,
    field_list      sysname,                                        --- created,link,...
    field_pk        sysname,                                        --- created,link,...
    field_stamp     sysname,                                        
    field_exception sysname,
    CONSTRAINT pk_merge_table PRIMARY KEY CLUSTERED (table_name)
)
GO

------------------------------------------------------------------------------
INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception ) 
                 VALUES ('Lake',       'IUD', 1, '', 'lake_id', 'stamp', '')
GO
INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception ) 
                 VALUES ('lake_fish',  'IUD', 2, '', 'lake_Id,fish_id', 'stamp', '')
GO

INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception ) 
                 VALUES ('lake_image',  'IUD', 2, '', 'lake_image_id', 'lake_image_stamp', '')
GO

INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception ) 
                 VALUES ('Lake_State',  'IUD', 2, '', 'Lake_id', 'stamp', '')
GO

INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception) 
                 VALUES ('Tributaries', 'IUD', 2, '', 'Main_Lake_id,Lake_id', 'stamp', 'id')
GO

INSERT INTO merge_table ( table_name,   operation, level, field_list, field_pk, field_stamp, field_exception) 
                 VALUES ('news',        'IU', 2, '', 'news_id', 'stamp', '' )
GO
------------------------------------------------------------------------------

