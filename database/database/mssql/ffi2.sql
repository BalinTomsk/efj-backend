use [master]
GO
create database [ffi]
GO
use [ffi]
GO
SET QUOTED_IDENTIFIER ON
GO
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
CREATE TABLE SessionHandler
(
    id         uniqueidentifier  NOT NULL,
    ipAddr     varchar(32) NOT NULL,
    startSess  datetime2 NOT NULL,
    endSess    datetime2,
    userAgent  nvarchar(255) NOT NULL,
    host       varchar(32) NOT NULL,
    startPage  varchar(255) NULL,
    userId     uniqueidentifier,
    sid        bigint identity(1,128)    
) 
GO
ALTER TABLE SessionHandler ADD CONSTRAINT PK_SessionHandler PRIMARY KEY CLUSTERED (id)
GO
ALTER TABLE SessionHandler add constraint df_SessionHandler_Id default NEWSEQUENTIALID() for [id]
GO
ALTER TABLE SessionHandler add constraint df_SessionHandler_startSess default getutcdate() for startSess
GO

-- select * from SessionHandler


-- update GlobalConfig table for number of visiters
CREATE TRIGGER trg_UpdateGlobalConfig
ON SessionHandler
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Determine the current day
    DECLARE @currentDay DATE = CAST(GETDATE() AS DATE);

    -- Check if the new IP addresses are already present for the current day
    IF NOT EXISTS (
        SELECT 1
        FROM SessionHandler
        WHERE CAST(startSess AS DATE) = @currentDay
        AND ipAddr IN (SELECT ipAddr FROM inserted)
    )
    BEGIN
        -- Update the global configuration if the condition is met
        UPDATE global_configuration
        SET config_value = (
            SELECT 500000 + SUM(UniqueIPCount)
            FROM (
                SELECT COUNT(DISTINCT ipAddr) AS UniqueIPCount
                FROM SessionHandler
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

-- select lakeId, lakename from WaterStation where lakeId not in (select lake_id from lake)

-- select mli, lat, lon from WaterStation where lakeId is null

-- update WaterStation set lakeId='0c53c2ab-849c-20c3-7b99-cbf904702ab4', lakename = 'Venison Creek' where mli = '02GC038'

-- delete from WaterStation where mli = '02GH016'

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
/*
	place to store meteo data for water stations from meteo services	
    http://api.weatherstack.com/current?access_key=5505cface519335581352f9e7093864a&query=40.7831,-73.9712
*/

CREATE TABLE ows_meteo
(
      WaterStation_id     uniqueidentifier NOT NULL primary key
	, mli                 varchar(64)
    , country             char(2)
    , state               char(2)
    , lat				  float
    , lon				  float
	, ows                 nvarchar(max)				-- JSON doc with weater
    , CONSTRAINT FK_ows_meteo_id  FOREIGN KEY ( WaterStation_id ) REFERENCES WaterStation(id)
    , CONSTRAINT FK_ows_meteo_mli FOREIGN KEY ( mli )             REFERENCES WaterStation(mli)
)
GO

CREATE UNIQUE NONCLUSTERED INDEX [UK_ows_meteo_mli] ON ows_meteo ( mli );
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
	DECLARE  @json nvarchar(max), @mli varchar(64), @WaterStation_id uniqueidentifier
	SELECT TOP 1 @json = ows, @mli = mli, @WaterStation_id = WaterStation_id FROM INSERTED
	EXEC sp_ows_meteo @json, @mli, @WaterStation_id
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
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'ProduceWBVariant' AND xtype = 'TF')
    DROP function dbo.ProduceWBVariant
GO
/*
    remove water body from name and produce all name variants
    select * FROM dbo.ProduceWBVariant( 'Naftel''s Creek' )
    select * FROM dbo.ProduceWBVariant( 'st. Peter' )
*/
CREATE FUNCTION dbo.ProduceWBVariant( @search sysname )
RETURNS @comb TABLE ( line sysname NOT NULL, irank int DEFAULT 0, id int not null identity(1,1)) 
WITH SCHEMABINDING
AS
BEGIN
	IF NULLIF(@search, '') IS NULL
		RETURN
	DECLARE @mix   TABLE ( line sysname, ln int IDENTITY(1,1) )

    INSERT INTO @mix (line) select RTRIM(LTRIM([value])) FROM STRING_SPLIT(@search,' ') WHERE NULLIF([value], '') IS NOT NULL

	DECLARE @cnt int = (SELECT MAX(ln) FROM @mix)

	-- find type of water body
	DECLARE @bodytype int = dbo.GetWaterType(@search)

	-- delete type of waterbody from name
	DELETE FROM @mix WHERE line IN (SELECT en FROM dbo.water_body e where dbo.GetValidPart(@search) = e.en
	                                    UNION SELECT fr FROM dbo.water_body f where dbo.GetValidPart(@search) = f.fr)

	SET @cnt = @cnt - 1

	-- make combinations
    INSERT INTO @comb  SELECT line, @cnt + 1 FROM @mix

	IF @cnt = 2
    BEGIN
		INSERT INTO @comb  SELECT m1.line + ' ' + m2.line as line, 2 FROM @mix m1, @mix m2 WHERE m1.line <> m2.line
    END ELSE
	IF @cnt = 3
    BEGIN
	    INSERT INTO @comb
		    SELECT m1.line + ' ' + m2.line + ' ' + m3.line as line, 2 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
	    INSERT INTO @comb
		    SELECT m1.line + ' ' + m2.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
            UNION 
		    SELECT m2.line + ' ' + m3.line as line, 3 FROM @mix m1, @mix m2 , @mix m3
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m2.line <> m3.line
    END ELSE
	IF @cnt = 4
    BEGIN
	    INSERT INTO @comb
		    SELECT m1.line + ' ' + m2.line + ' ' + m3.line + ' ' + m4.line as line, 2 FROM @mix m1, @mix m2 , @mix m3, @mix m4
			    WHERE m1.line <> m2.line AND m1.line <> m3.line AND m1.line <> m4.line AND m2.line <> m3.line AND m2.line <> m4.line AND m3.line <> m4.line
    END
	ELSE 
		INSERT INTO @comb select line, 1 FROM @mix

    -- delete duplicats
    delete x from (  select line, rn=row_number() over (partition by line order by irank)  from @comb) x where rn > 1;

	-- table for expanding
	DECLARE @expander TABLE ( val sysname, en nvarchar(64) )
	INSERT INTO @expander (val, en) VALUES (N'St.', N'Santa');

    -- add variant based on synonims
	WITH cte AS
	(
		SELECT c.line, x.[value], irank FROM @comb c CROSS APPLY (select RTRIM(LTRIM([value])) FROM STRING_SPLIT(c.line,' ') WHERE NULLIF([value], '') IS NOT NULL)x(value)
			WHERE EXISTS ( SELECT en FROM @expander e WHERE x.[value] = e.val UNION SELECT val FROM @expander e WHERE x.[value] = e.en)
	)
 	INSERT INTO @comb	-- insert expanded variants: St. => Santa
		SELECT REPLACE(cte.line, cte.[value], e.en), irank + 1  FROM cte JOIN @expander e ON cte.[value] = e.val
		UNION ALL 
		SELECT REPLACE(cte.line, cte.[value], e.val), irank + 1 FROM cte JOIN @expander e ON cte.[value] = e.en

    -- add variant or/with surrounded apostofs
    INSERT INTO @comb (line, irank)
        SELECT RIGHT(val, LEN(val)-1) AS line, irank FROM ( SELECT LEFT(line, LEN(line)-1) AS val, irank + 1 AS irank FROM @comb 
            WHERE (RIGHT(line, 1) = '"' AND LEFT(line, 1) = '"') OR (RIGHT(line, 1) = '''' AND LEFT(line, 1) = '''') )x

    -- add variant or/with apostof with s
    INSERT INTO @comb (line, irank)
        SELECT REPLACE(line, '''s', 's'), irank + 1  FROM @comb WHERE RIGHT(line, 2) = '''s'
    INSERT INTO @comb (line, irank)
        SELECT REPLACE(line, '''s', ''), irank + 1  FROM @comb WHERE RIGHT(line, 2) = '''s'
    INSERT INTO @comb (line, irank)
        SELECT REPLACE(line, '''s', ''), irank + 1  FROM @comb WHERE RIGHT(line, 2) = 's'

    -- add variant or/with proclamation mark
    INSERT INTO @comb (line, irank)
        SELECT REPLACE(line, '!', ''), irank + 1  FROM @comb WHERE RIGHT(line, 1) = '!'

	-- restore @search without bodytype
	DECLARE @srch sysname = ' ';
	SELECT @srch = @srch + N' ' + line FROM @mix ORDER BY ln ASC

	UPDATE @comb SET irank = 1 WHERE line = LTRIM(@srch)

	DELETE FROM @comb WHERE line in ( 'arm', 'creek', 'lake', 'stream', 'channel', 'pond', 'marsh', 'backwater', 'canal', 'estuary', 'shore', 'drain', 'ditch', 'wetland', 'reservoir', 'sea')
	DELETE FROM @comb WHERE line in ( 'bras', 'ruisseau', 'lac',  'étang', 'marais', 'eau stagnante',   'estuaire', 'rivage',   'fosse', 'réservoir', 'mer')

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
RETURNS @result TABLE ( line sysname NOT NULL, irank int ) 
WITH SCHEMABINDING
AS
BEGIN
	IF NULLIF(@search, '') IS NULL
		RETURN

	-- make combinations
	DECLARE @comb TABLE ( line sysname NOT NULL, irank int DEFAULT 0, id int not null identity(1,1)) 

    INSERT INTO @comb  SELECT line, irank FROM dbo.ProduceWBVariant( @search )

    IF EXISTS (SELECT line FROM @comb WHERE RIGHT(line, 1) = '!')
        INSERT INTO @result SELECT REPLACE(@search, '!', ''), 1

	INSERT INTO @result SELECT @search, 0

	INSERT INTO @comb SELECT s.value + N' ' + line, irank + 1 FROM @comb c
	    , STRING_SPLIT(N'Big,Small,Little,Left,La gauche,Right,Droite,Upper,Lower,North,Nord,South,Sud,West,Ouest,East,est',',') s
        WHERE line NOT LIKE (value + ' %')

    DECLARE @bodytype int = dbo.GetWaterType( @search );

	-- add all combinations of water body
	IF @bodytype IS NOT NULL
	BEGIN
		DECLARE @prepare TABLE ( line sysname NOT NULL, irank int);

        WITH cte (val) AS
        (
            SELECT en FROM dbo.water_body WHERE locType = @bodytype
            UNION
            SELECT fr FROM dbo.water_body WHERE locType = @bodytype
        )
        INSERT INTO @prepare 
            SELECT val  + N' ' + line, irank FROM @comb, cte
            UNION
            SELECT line+ N' ' + val, irank FROM @comb, cte

		INSERT INTO @result SELECT DISTINCT line, irank FROM @prepare c WHERE NOT EXISTS (SELECT line FROM @result r WHERE r.line = c.line)
	END
		ELSE 
			INSERT INTO @result SELECT DISTINCT line, 1 FROM @comb c WHERE NOT EXISTS (SELECT line FROM @result r WHERE r.line = c.line)

    delete x from (  select line, rn=row_number() over (partition by line order by irank)  from @result) x where rn > 1;
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
-- SELECT * FROM dbo.fn_river_list( 'ON', 'CA', 1, N'S', 0, 1, 0) where reviewed = 1  ORDER BY lake_name ASC
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
                , COALESCE(source_loc, mouth_loc, CGNDB) AS guidloc, symbol, reviewed
            FROM dbo.vw_lake l
            WHERE @state IN (source_state, mouth_state) AND @river = l.locType
            AND ISNULL(isFish,0)  = (CASE WHEN @fish    = 1 THEN 1 ELSE 0 END)
            AND ISNULL(isWell,0)  = (CASE WHEN @monitor = 1 THEN 1 ELSE 0 END)
            AND l.lake_id IN (SELECT lake_id FROm dbo.lake WHERE symbol in ('0','1','2','3','4','5','6','7','8','9')
                        UNION SELECT lake_id FROm dbo.lake WHERE symbol=UPPER(@section)
                        UNION SELECT lake_id FROm dbo.lake WHERE @section='$'  )
    )SELECT num, lat, lon, lake_name, alt_Name, county, lake_id, state, country, [description], zone
        , IsFish, isWell, source_name, mouth_name, source_lat, source_lon, mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB, guidloc 
		, x.cnt  AS itg, sym, reviewed
        FROM
        (
            SELECT ROW_NUMBER() Over(Order by (Select 1)) AS num, lat, lon, lake_name, alt_Name, county, lake_id, state
                 , country, [description], zone, IsFish, isWell, source_name, mouth_name, source_lat, source_lon
                 , mouth_lat, mouth_lon, source_loc, mouth_loc, CGNDB, guidloc, symbol AS sym, reviewed FROM cte
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
-- SELECT * FROM [dbo].[fn_get_trial_location]( 'Bass, rock', 43, -80 )
**/
CREATE function dbo.fn_map_location( @fishName  varchar(64), @lat float, @lon float, @dist float )
  RETURNS  TABLE
  WITH SCHEMABINDING
AS
RETURN   --lat, lon, today, location, sid, country, state, county
    SELECT  w.lat, w.lon, f.today, w.LocName AS location, w.sid, w.country, w.state, w.county 
        FROM dbo.vWaterStation w 
        JOIN dbo.fish_location f ON ( f.station_Id = w.id )
        JOIN dbo.fish          s ON ( f.fish_Id    = s.fish_Id )
        WHERE s.fish_name = @fishName
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
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon( 40, -81, 3  )
CREATE FUNCTION dbo.fn_map_fish_list_bylatlon( @lat real, @lon real, @dist real  )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT fish_id, fish_name FROM dbo.fish v
    WHERE ( v.fish_Type & 1 ) = 1 AND EXISTS         -- 1 - sport fish
    ( 
		SELECT TOP 1 1 FROM dbo.fish_location f 
			JOIN dbo.WaterStation w ON (f.station_Id = w.id)
			WHERE f.fish_id = v.fish_id 
			AND ( w.lat between (@lat-@dist) AND (@lat+@dist) )
			AND ( w.lon between (@lon-@dist) AND (@lon+@dist) )
    )      
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_map_fish_list_bylatlon_trial' AND xtype = 'IF')
    DROP function dbo.fn_map_fish_list_bylatlon_trial
GO
-- Called from  FishTracker.Forecast.MapFrame.LoadInitialFishes
-- SELECT * FROM dbo.fn_map_fish_list_bylatlon_trial( 40, -81   )
CREATE FUNCTION dbo.fn_map_fish_list_bylatlon_trial( @lat real, @lon real  )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
SELECT v.fish_id, fish_name FROM dbo.fish v
    LEFT JOIN dbo.fish_zoo z ON z.fish_id = v.fish_id
    WHERE ( v.fish_Type & 1 ) = 1 AND EXISTS         -- 1 - sport fish
    ( 
		SELECT TOP 1 1 FROM dbo.fish_location f 
			JOIN dbo.WaterStation w ON (f.station_Id = w.id)
			WHERE f.fish_id = v.fish_id 
			AND ( w.lat between (@lat-0.5) AND (@lat+0.5) )
			AND ( w.lon between (@lon-0.5) AND (@lon+0.5) )
    ) AND z.fish_max_length < 45
GO
---------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_read_fish_edit_list' AND xtype = 'TF')
    DROP function dbo.fn_read_fish_edit_list
GO
-- 1 - sport, 2 - Coarse, 4 - commersial, 8 - invading
-- select * from dbo.fn_read_fish_edit_list() where fish_id = '6b45fea3-5cbe-4982-89af-c241eb5c6a36'  ORDER BY fish_name ASC
CREATE FUNCTION dbo.fn_read_fish_edit_list()
RETURNS @TBL TABLE ( fish_id uniqueidentifier, fish_name varchar(32), fish_latin varchar(64), synonims  varchar(255) 
         , food_Type int, water_type int, feedsOver int , habitat int
         , tuLD float, tuL float, tuC float, tuH float, tuHD float 
         , tmLD float, tmL float, tmC float, tmH float, tmHD float
         , oxLD float, oxL float, oxC float, oxH float, oxHD float
         , phLD float, phL float, phC float, phH float, phHD float
         , veL float, veH float
         , depthMin float, depthMax float
         , saltL float, saltH float
         , NitrateH float, NitrateL float, PhosphateH float, PhosphateL float
         , periodStart int , periodEnd int, editor varchar(128), locked bit
         , fish_Type int, fish_ability int, react_color int, home_range float, stamp datetime )
WITH SCHEMABINDING
AS
begin
  -- get non-spawn period
  INSERT INTO @TBL ( fish_id, fish_name, fish_latin, synonims, food_Type
                   , water_type, fish_Type, fish_ability, react_color, home_range, stamp )
        SELECT fish_id, fish_name, fish_latin, alt_Name, food_Type, water_type, fish_Type
        , fish_ability, react_color, fish_home_range, stamp FROM dbo.fish;

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
     FROM @TBL t JOIN dbo.fish_Rule c ON t.fish_id=c.fish_id  WHERE -1 = c.periodStart AND -1 = c.periodEnd
  return
end
GO
--------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sysobjects WHERE NAME = 'fn_edit_fish_general' AND xtype = 'IF')
    DROP function dbo.fn_edit_fish_general
GO

-- Called from  FishTracker.Editor.FishGeneral.LoadGeneralFish
-- SELECT * FROM [dbo].fn_edit_fish_general('a85ebf22-4ab9-4a91-a14a-cef6c8e64d97')
-- SELECT TOP 1 fish_image_id FROM dbo.fish_image WHERE fish_id = '6b45fea3-5cbe-4982-89af-c241eb5c6a36'
CREATE FUNCTION [dbo].[fn_edit_fish_general]( @fish_id varchar(36) )
RETURNS TABLE
WITH SCHEMABINDING
AS
  RETURN
    SELECT TOP 1 fish_latin, fish_name, alt_name AS fish_alt_name, descrip AS fish_description 
        , locked, stamp, (select userName from dbo.users where id=editor) AS editor 
        , (SELECT TOP 1 fish_image_id FROM dbo.fish_image WHERE fish_id = @fish_id ORDER BY fish_image_stamp DESC) AS fish_image_id
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
RETURNS @TBL TABLE ( sid int not null primary key, fish_name sysname, fish_id uniqueidentifier, link nvarchar(2048), source_type int )
WITH SCHEMABINDING
AS
BEGIN
    INSERT INTO @tbl
    SELECT t.sid, fish_name, t.fish_id, t.link, probability_source_type
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
                SELECT dbo.fn_lake_fish('fc0d917b-d053-11d8-92e2-080020a0f4c9');
 */
CREATE function dbo.fn_lake_fish(@lake uniqueidentifier)
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
    , type int );

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

    DECLARE @result XML =
    (SELECT noFish, is_fishing_prohibited, isFish, fishing, lake_name, Lake_id, Reviewed,
        (SELECT sid, fish_name, fish_id, link, source_type, type FROM @TBL [fish] ORDER BY fish_name ASC FOR XML AUTO, TYPE)
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
 Each River has list of regulations
 */
CREATE FUNCTION dbo.fn_GetLakeRegulations( @lake_id uniqueidentifier )
  RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN
    WITH cte AS 
 (
    SELECT ROW_NUMBER() over (ORDER BY fish_id, level ASC) AS num, fish_id, regulations_id, level FROM
    (
        SELECT fish_id, regulations_id, 1 AS level FROM dbo.regulations WHERE lake_id = @lake_id
        UNION ALL
        SELECT fish_id, regulations_id, 2 FROM dbo.regulations r 
            JOIN dbo.fn_GetAllLakeZones( @lake_id ) z ON r.zone_id = z.zone_id WHERE r.lake_id Is NULL
        UNION ALL
        SELECT fish_id, regulations_id, 3 FROM dbo.regulations r JOIN dbo.fn_GetAllLakeStates( @lake_id ) z ON r.state = z.state WHERE r.lake_id Is NULL AND zone_id IS NULL
    )x
)   SELECT r.regulations_id,[regulations_part],[state],[zone_id],[Lake_id],[fish_id],[chain],[regulations_date_start],[regulations_start]
           ,[regulations_date_end],[regulations_end],[regulations_sport],[regulations_sport_text],[regulations_consr],[regulations_consr_text]
           ,[regulations_code],[regulations_link],[regulations_stamp],[regulations_text]
        FROM dbo.regulations r JOIN
        (SELECT regulations_id FROM cte WHERE num IN (SELECT MIN(num) AS num from cte GROUP BY fish_id)) z ON z.regulations_id = r.regulations_id
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
 select * FROM dbo.fn_GetTopNews('4b3c2821-af05-4790-9fb8-37f6ba6abf7c')
 */
CREATE FUNCTION dbo.fn_GetTopNews( @newsId uniqueidentifier )
  RETURNS TABLE 
AS
RETURN
    select news_id, news_stamp, country, news_title, news_author_link, news_author, news_source_link, news_source
         , news_photo_author0, lake_id, news_paragraph0, news_paragraph1, news_photo0, 0 AS ORD, id
         , (select fish_name from fish f where f.fish_id = fish1_id) AS fish1_name
         , (select fish_name from fish f where f.fish_id = fish2_id) AS fish2_name
         , (select fish_name from fish f where f.fish_id = fish3_id) AS fish3_name
         , (select lake_name from lake l where l.lake_id = n.lake_id) AS lake_name
         FROM news n WHERE news_id = @newsId AND news_title <> 'title' 
    UNION 
    select top 24 news_id, news_stamp, country, news_title, news_author_link, news_author, news_source_link, news_source
         , news_photo_author0, lake_id, news_paragraph0, news_paragraph1, null AS news_photo0, 1, id 
         , null, null, null, null
        FROM news WHERE news_id <> @newsId AND news_title <> 'title' ORDER BY id DESC
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
-----------------------------------------------------------------------------------------------------------------------------------------------
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
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- https://en.wikipedia.org/wiki/Body_of_water
------------------------------------------------------------------------------------------------------------------------------------------------------------
--  1 - lake, 2 - river,  4 - stream, 8 - pond, 16 - marsh, 64 - creek
--  128 - canal, 8192 - Reservoir, 16385 - Sea
--  0 - lake, 1 - slow moving, 4 - normal moving, 8 - stream, 816- fast stream

INSERT INTO water_body (en, fr, locType, speed, description) VALUES
   ('Lake',      N'Lac',                        1, 0, 'a body of water, usually freshwater, of relatively large size contained on a body of land')
 , ('Reservoir', N'R'+nchar(233)+N'servoir', 8192, 0, 'Artificial lake or artificial pond')
 , ('Bay',       N'Baie',                       1, 0, 'Bay')
 , ('Brook',     N'Ruisseau',                64,   8, 'a small stream')
 , ('Burn',      N'Br' + nchar(251)+ N'ler', 64,   8, 'a small stream')
 , ('Canal',     N'Canal',                   128,  8, 'an artificial waterway, usually connected to (and sometimes connecting) existing lakes, rivers, or oceans')
 , ('Channel',   N'Canal',                   128,  8, 'the physical confine of a river, slough or ocean strait consisting of a bed and banks.')
 , ('Creek',     N'Ruisseau',                64,   8, 'a small stream')
 , ('Ocean',     N'Oc'+nchar(233)+N'an',     16385,0, 'a major body of salty water that, in totality, covers about 71% of the Earth''s surface')
 , ('Pond',      nchar(201)+N'tang',         8,    0, 'a body of water smaller than a lake, especially those of artificial origin')
 , ('River',     N'Rivi'+nchar(233)+N're',   2,    4, 'a natural waterway usually formed by water derived from either precipitation or glacial meltwater, and flows from higher ground to lower ground')
 , ('Run',       N'Courir',                  64,   8, 'a small stream or part thereof, especially a smoothly flowing part of a stream.')
 , ('Strait',    N'D'+nchar(233)+N'troit',   128,  0, 'a narrow channel of water that connects two larger bodies of water, and thus lies between two land masses')
 , ('Stream',    N'Courant',                 4,    8, ' a body of water with a detectable current, confined within a bed and banks.')
 , ('Sea',       N'Mer',                     16385,0, 'a large expanse of saline water connected with an ocean, or a large, usually saline, lake that lacks a natural outlet such as the Caspian Sea and the Dead Sea.')
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO fish_family (Family_id, Family_name, fid) VALUES
 ('00000000-0000-0000-0000-000000000000','none',100001)
,('969E5641-010F-4E55-8E2C-00A04979F2CF','Ctenoluciidae',146)
,('BE0EF627-8175-4993-AC1D-011163CBD5C2','Amiidae',21)
,('B0DC05BB-D217-4EF1-A627-01722021DCB9','Cynoglossidae',151)
,('627C23DB-0AB2-49BF-BB06-02A070BB2D7E','Oplegnathidae',347)
,('E6D4A07D-CA3F-42AF-9A5C-0377EB1816DC','Akysidae',11)
,('DC296C29-D416-4B75-A021-0418F253DC1B','Barbourisiidae',61)
,('D0BAC89B-31F1-43BA-97A1-04BAF253BFEB','Holocentridae',239)
,('40E30C92-E104-4BC4-BC1C-04C1C3F13BE6','Notacanthidae',330)
,('7C4DCB07-BB0C-422A-9CDE-04F4F188AC49','Centropomidae',100)
,('26191D20-F733-415F-9545-050F90E13FFC','Gnathanacanthidae',206)
,('C9AF3177-5C0F-4FB6-987F-05CCBEA60B4B','Percophidae',376)
,('3A1A1AEE-F115-4B4F-A4EE-05E2ADAE8FCA','Odacidae',336)
,('647023D2-10F5-439A-A4BB-072F456A13AA','Ipnopidae',247)
,('5D16A36C-1C77-4377-9D30-0730DAF71843','Synanceiidae',483)
,('23E3A6DD-6199-4DB8-A811-08347678992B','Monacanthidae',301)
,('18C87C24-ACDC-4350-BD34-0864F40BE79E','Heterodontidae',231)
,('9B973A7F-D336-4D98-9DA2-08B57D92200A','Salangidae',440)
,('A75A3BD6-C5FD-43A0-B3BF-08D58A49F20D','Fistulariidae',192)
,('61D3D71F-B080-44CE-895A-08FD721F4AA6','Bythitidae',79)
,('48F0CA4F-F6BB-40D8-BD6E-09A5BFE8E3A0','Indostomidae',245)
,('7DC5A29A-60E8-481C-B01A-09AA7ACD6E9D','Dinolestidae',163)
,('0C45C3F2-3BB8-4EB3-BD7E-09E0EC453ABD','Solenostomidae',467)
,('538E1D18-EF82-49EF-AFE8-09FF7F9FBF8A','Caulophrynidae',92)
,('6B0D3CFE-7E3B-4109-A3A7-0A14C860850D','Scombridae',450)
,('49A462FC-4C00-454A-93BC-0A9BC3461CB2','Tripterygiidae',509)
,('21ECC6A5-AA25-4254-BB9A-0B0379AE3315','Ostraciidae',353)
,('5BEF9BDE-DF27-40E0-88AD-0B4DBC012540','Stromateidae',479)
,('50AA0331-6D57-4AC6-A195-0BA5A6AAE650','Centrophrynidae',99)
,('2B888832-C76F-40B2-840E-0C5F92AD6736','Electrophoridae',174)
,('ECFCBD27-0586-4843-9571-0C7E8AF56F85','Toxotidae',496)
,('2506BBF6-1C0E-4C01-BA36-0CCCF9917157','Gymnotidae',215)
,('757BF8C8-0CA7-4A81-8D03-0D5B598CC02A','Trachipteridae',499)
,('0F99EE3B-E4A4-4423-8320-0DB8D3B63129','Olyridae',340)
,('2177A204-800D-413C-9FE9-0E0E0F9D28D4','Salmonidae',441)
,('87F2373F-0D6E-4F86-9A17-0EC1E678EC2A','Merlucciidae',294)
,('EF7711FC-D13F-4CD8-B14A-0FDD5C26BFC8','Grammicolepididae',213)
,('EBFBD2E6-B4B8-4617-8EFB-105FEAF68116','Polyodontidae',400)
,('88E4C194-1898-4543-A6D6-11786FF2ED7C','Ophidiidae',344)
,('D57BA1EB-F32B-459A-8931-11D04ECB5FF7','Hiodontidae',237)
,('69B57A0D-882E-40A3-940A-11DFF0E0D4B3','Lampridae',258)
,('FA6F3E14-2860-407D-85EB-126AAE1D7488','Congridae',138)
,('A8C3F042-CEDC-44C3-87CA-1281A631DDD5','Hexatrygonidae',235)
,('BF791321-53FE-4C3C-8914-12ECB684B6C6','Cichlidae',126)
,('BC3CC828-2A16-41EF-801E-130253F3F07F','Veliferidae',514)
,('F96085FC-E663-48E3-9234-13291EF8E989','Dinopercidae',164)
,('2E69EB25-698D-4EAC-A1F1-135ADA74A7D4','Banjosidae',60)
,('26EC1927-5062-41E8-89B2-139C8EE021F8','Cheilodactylidae',117)
,('E57FEACF-A3C4-4BBB-B97F-13D74487EF02','Labridae',254)
,('8D632FF3-DB3B-4836-A67B-148DA5C8A34F','Chimaeridae',120)
,('73143339-8629-49BC-A81F-15AA82F83200','Gerreidae',200)
,('7A9EDA78-7AA8-41E4-BA35-162AD8D26F43','Aulostomidae',56)
,('263527A1-D318-40B2-A0B3-1653BF8D93A2','Nematogenyidae',321)
,('D5B2D33F-3D7D-4BE1-814A-165C6678EA58','Hispidoberycidae',238)
,('BBAE73C9-A2C1-4A55-83D8-16A013F24DF1','Parabrotulidae',359)
,('3F238A77-18DA-4A0E-8128-17219F6080F2','Carapidae',88)
,('5A9D3C2D-4EB7-4447-9E86-1771E2C681C2','Heptapteridae',229)
,('941775A2-A9E1-4759-8559-17B15DB6DE7A','Ictaluridae',244)
,('3359F071-EE56-49CC-AFBE-19A124DA37B1','Synbranchidae',485)
,('1BDCEFCC-7F96-4299-8EB0-19EEC9A3D816','Pseudocarchariidae',416)
,('8B698EF3-3ABF-4A7D-B32C-1B2E8537504B','Plectrogenidae',391)
,('B19E4071-3C1E-411A-A954-1B5EEB847FD2','Chlorophthalmidae',125)
,('4F12ADCB-7374-4E80-885B-1C8C03D614BD','Gyrinocheilidae',217)
,('CCC9F83F-A632-41EB-BB68-1CF9A2BC57DB','Scyliorhinidae',456)
,('A5B1B00E-21B1-4475-A357-1EE8B6F5F50D','Caracanthidae',86)
,('85EA5FFC-B324-4059-9FBC-1EFA0017C636','Notopteridae',333)
,('1E7992EE-B9CF-45CA-87D6-1FBEF1449961','Psilorhynchidae',422)
,('D664EB73-BCAF-4ED2-803E-20DF79BB8051','Cyprinidae',152)
,('37A7C146-04CF-4FB3-8BCA-2138C4E692B4','Synodontidae',487)
,('95C3722E-A28C-4947-A6B7-21E1F40BAE64','Trichonotidae',506)
,('8345C0F5-17A0-4BC8-9A52-21EC3148091E','Dichistiidae',162)
,('31485BA1-42BF-4C77-B63B-224187080AF7','Osteoglossidae',352)
,('9F5E0B5F-40EC-4565-8FF6-224EC88FBD40','Sebastidae',458)
,('89C59B6D-A959-4746-9429-23074C245823','Kuhliidae',251)
,('AE1AF879-30C9-4D59-90AA-234E74D0EB1B','Prochilodontidae',410)
,('FF5886FF-E158-4D0E-8B9E-243CE3EA7431','Parabembridae',358)
,('A5012CF1-C1FC-4B5B-993E-24A072F0097A','Ephippidae',182)
,('0F0DCD68-F897-4FD0-8E44-251B94FE41FE','Chlopsidae',124)
,('A017091F-C268-4C93-987F-25CE9A15B521','Synaphobranchidae',484)
,('9A61E2E7-DA3C-44E1-BCFC-2702B609EF6D','Heteropneustidae',232)
,('FBC27C26-81AB-4778-A3C8-27214ED6140C','Monognathidae',304)
,('D4A8B0ED-65A9-4CB4-9B3C-282FC777436A','Cottidae',140)
,('9C3B4630-DD18-4C31-8B68-2859853070AC','Rhinochimaeridae',435)
,('2AD81F9A-0ACA-4236-BD52-2899927EC609','Doradidae',168)
,('335F8671-8354-43E9-8288-291D62CA84B3','Pristiophoridae',409)
,('B4921A60-895C-4950-84B6-29409528ED3D','Oxynotidae',355)
,('ED96C48E-43C3-4C04-9195-2A0BD7566A79','Neoscopelidae',325)
,('D62CEC37-5477-492B-8570-2A11143CFE6D','Pempheridae',370)
,('4F8BD23A-952E-489F-88CF-2A60155E41FE','Plecoglossidae',390)
,('B9339717-E9CE-452D-B289-2ABE883EC967','Torpedinidae',495)
,('A60F8B06-E72B-44A0-9F28-2C8DB717DC79','Congiopodidae',137)
,('A336546F-67DA-4C6C-B9B6-2CBC9B906B35','Perciliidae',375)
,('EABA2354-1522-4798-AAAB-2CF821AF8D51','Dactyloscopidae',155)
,('664F5115-CAC9-47CF-9F22-2D0B0EB0667A','Gonorynchidae',209)
,('65602359-3AC9-4304-9A46-2DC7619DF12C','Lepisosteidae',265)
,('04C8893C-FA7C-4A06-9D4A-2E4375FBA7EC','Oreosomatidae',349)
,('82CD5EE7-EBE8-4908-9AC4-2E719549D854','Phycidae',385)
,('4690EA21-A51D-43B9-A626-303792A4618A','Lotidae',278)
,('2AC017EA-DECD-46E1-95D3-3072DA61CB82','Colocongridae',135)
,('DD9B5772-0EAE-479F-ACF4-30F6ACDFF449','Coryphaenidae',139)
,('A8409A18-0EF5-4E4C-99EB-316B09D627C6','Pentacerotidae',371)
,('7F649BB4-A8FD-4CCD-8B6C-31A543914624','Dactylopteridae',154)
,('D3C3D33A-1195-4F13-AF09-31DFE66F9FCE','Anostomidae',32)
,('29AF8076-3BD9-41A7-87F8-32552F43711A','Hoplichthyidae',240)
,('B263988A-98DD-4D4C-9C08-325633797E01','Brachionichthyidae',76)
,('DA8AD379-75CC-4F35-A85C-329AC64A64A5','Siluridae',464)
,('64F58566-45D7-4914-BA72-32BB49B36E4F','Tetrabrachiidae',490)
,('9BF3D717-B3D4-4971-9512-32E576B8B3B8','Eleginopidae',175)
,('7E85FB92-DC2C-4DE2-958F-32E5FEF188AE','Comephoridae',136)
,('9705134E-7D0C-41B0-9B41-336779E51CB8','Hepsetidae',228)
,('1BC30680-3625-4D23-B96A-33F43B66681E','Zeidae',520)
,('527A00B7-3F4A-4AD0-9AB7-3657F048C2A0','Rhincodontidae',433)
,('97A628AD-75B1-4839-8986-36D16F7C741D','Kneriidae',249)
,('1394AB84-00E4-424C-B39C-370E71283051','Geotriidae',199)
,('CECAD049-9D29-4015-A8B6-3782ED51A7B8','Cirrhitidae',127)
,('EAF76AF5-C095-475F-ADE4-385AA37AEFA8','Leptochilichthyidae',268)
,('02016E33-AC30-4E0F-8720-3924ED2F306D','Squalidae',471)
,('4BA18F5B-679C-43C9-BAB9-39A1117F0175','Lophotidae',276)
,('4CF42BD2-6D7D-4859-A249-3A2A358F1DFF','Bedotiidae',68)
,('32A03CBF-C665-4316-B261-3A2CB4FEF2E1','Chacidae',107)
,('B75CDFAA-E5A4-41F7-AF64-3A4ABEE7FA27','Characidae',114)
,('FF14E154-FDE8-4A17-8688-3A8BB5392FDA','Ceratiidae',102)
,('57894706-676E-4FDF-9436-3B7CB12BDF05','Notocheiridae',331)
,('9E4999E5-8052-41F6-8366-3B88BCF26E57','Parodontidae',367)
,('A45EA295-BEB2-430D-9775-3B8B9061E9DF','Rondeletiidae',438)
,('6C653002-53E5-46E9-8ED3-3BA2E52C8FC8','Centriscidae',95)
,('632528F2-7DDD-4B9F-96A7-3C3F3617AB96','Stomiidae',478)
,('F6CC345F-7411-4C13-91B5-3CEC1C6B2F2E','Mirapinnidae',297)
,('8748C2DF-A040-46E0-A4B8-3D22EB67B5BB','Pristidae',408)
,('43FAF742-2947-41F8-B42D-3E4BA4DBF093','Acanthuridae',2)
,('FF79DD18-F255-42BE-B0C1-42BEAFB3E4DA','Narcinidae',319)
,('7A69AA59-576D-4B84-A02A-42D0109CB1CB','Megachasmidae',286)
,('F8814898-7C27-4840-AE2F-437517D014A9','Sparidae',468)
,('FC31BCDA-44E1-44DB-B0E4-438E7772154A','Nematistiidae',320)
,('F27AB457-38F6-46A4-B33C-447CF495EA8E','Labrisomidae',255)
,('832F1AF4-4433-4EE8-8FA5-45A3D710D08E','Ptereleotridae',424)
,('BE1278BE-E64D-47A6-8E21-46B9A0F3F291','Callanthiidae',81)
,('37FA9B02-3CCA-4114-B0E1-46DBDF1D361F','Microdesmidae',295)
,('74F704CB-7681-4044-ADEA-4701869887F2','Notograptidae',332)
,('C58849E5-53E3-4FF1-BF10-47B5453275D3','Gasterosteidae',197)
,('CD096A45-5E2B-4549-8299-48E29C6EB394','Plesiopidae',393)
,('CB92665F-0836-4775-B486-4967345D0654','Derichthyidae',160)
,('F7435DE6-E8AE-4FBC-8635-4ADCC0A75AF5','Umbridae',510)
,('04297231-AD35-4322-BD2F-4B1DA20E4B29','Aulorhynchidae',55)
,('7885FCB8-3FA5-4FB3-8FEE-4B41A72017EA','Gadidae',194)
,('B9495DE5-DD67-41E0-BAEF-4B73E4F2FF12','Notosudidae',334)
,('EBA52918-1D87-4D61-B616-4B9D3B653F4F','Rhamphichthyidae',431)
,('595915D8-9789-4DD2-9A6F-4BD386122392','Sphyraenidae',469)
,('A189FC0D-59CB-4CE9-858E-4BED17A26EDA','Rivulidae',437)
,('0B3A843E-F8E9-407A-8036-4C74FE09F98C','Alestiidae',15)
,('8A08C3AB-80F7-4E4E-8936-4C762757EF7B','Pseudaphritidae',415)
,('4C3A1B68-1057-4852-AAD3-4D16BE55A32A','Goodeidae',211)
,('75FAD1C0-DA35-421A-B613-4D191B6E6303','Proscylliidae',412)
,('85DD5BB7-7869-473D-9733-4EA17C1F0E4A','Nemichthyidae',322)
,('C71C6A23-0158-4125-A6B9-504B2D2FD049','Citharidae',128)
,('490A5B40-2DC8-4288-85DF-50928AA05C75','Ariommatidae',45)
,('61B5046E-60B4-4674-B1C8-50D0BAFA0468','Chirocentridae',121)
,('ED878BFD-D7D3-4EB6-9B03-50FB91273A94','Hemitripteridae',227)
,('D669DB3C-0485-44DB-B3A4-533600079DB9','Himantolophidae',236)
,('D8CF67A5-381A-4DC9-A8ED-544C5F1403EE','Neosebastidae',326)
,('71CB46FC-E054-4031-BFCF-5485E71259A5','Embiotocidae',178)
,('D218C1CA-2444-40D3-BF66-54F4941CE3F9','Helogeneidae',221)
,('DEA52799-AFDC-414F-8111-5541AC430788','Luvaridae',281)
,('9FF81898-02ED-4AA9-AD94-558198ABE92B','Muraenolepididae',313)
,('E8B79F62-F1C0-4A51-9D4E-56ACECADE237','Stephanoberycidae',474)
,('666CFE95-AFE6-4CB7-84CE-57054D0AC079','Halosauridae',219)
,('0A47C304-99F9-44EF-949B-57224F6D9AD0','Microstomatidae',296)
,('21798FAE-84DD-42CD-A553-574DCA2EB4BC','Callichthyidae',82)
,('8B825BD2-0B6A-49BD-BF4D-579D85C1CA68','Channidae',113)
,('C304BA90-2BB5-458D-9430-58ED5C10DAC9','Apteronotidae',42)
,('0F4AD93F-5692-4E1F-897C-598F7974BA27','Gobiesocidae',207)
,('21BF66C5-E2F1-4495-BF77-599B80213463','Nototheniidae',335)
,('3BF00FB7-D435-44D4-97D4-59AEF69B34DE','Kraemeriidae',250)
,('4397ECE3-8C9D-47F4-BC79-5AD029BFC072','Osphronemidae',351)
,('3FE45295-A78B-44F6-8C9E-5B41CD341EAB','Diodontidae',165)
,('620FE439-6267-43D5-AC38-5C12C8706B85','Aulopidae',54)
,('379EB483-4C8A-4D46-AFB4-5C9FC1BDED69','Loricariidae',277)
,('C52E1A7F-EDC5-458A-8708-5DC7F89FAE6A','Aplodactylidae',40)
,('2894876E-8311-401D-A158-5DFC43DA63CE','Hexagrammidae',233)
,('19B39A2A-529D-4FEB-A29F-5F50AA6BD408','Albulidae',12)
,('42D01CA3-126D-42A3-893C-5FBF28A54368','Acestrorhynchidae',3)
,('60593FB6-4775-4DDD-B412-600B2BA00769','Trachinidae',498)
,('13139F90-882F-4EB3-9D6B-60EBAB8FCBB1','Pantodontidae',357)
,('78EF549B-6A2D-4D8E-8C2E-60F02DBD26DF','Triakidae',502)
,('44047F92-B512-4528-97B6-61418197A0B1','Cetorhinidae',106)
,('8E6B0EA9-6438-414C-BD33-6145EC397B00','Adrianichthyidae',8)
,('F6AC2BD1-C305-484D-8630-617E4B1DD573','Rhyacichthyidae',436)
,('DEE31BA8-8221-47BF-A951-61E03F698050','Latimeriidae',259)
,('55271462-9823-48F2-86F7-6236CC6F3550','Peristediidae',378)
,('98C55BAC-3FC1-4DC4-8F2C-62D70116CC81','Ateleopodidae',50)
,('F4C787E9-AD98-4D64-85DD-645348A0CB01','Denticipitidae',159)
,('ACAF8333-89BB-4F22-A406-645B4D41B33F','Regalecidae',429)
,('11745BE9-E557-4711-AE64-65399D918857','Stegostomatidae',473)
,('6F3507B2-A9FC-49A0-BC58-65441EB3AD67','Amblycipitidae',19)
,('71DD5132-2F64-43B7-8EC1-65D861839A59','Exocoetidae',191)
,('D31FBAA7-D9A0-4D60-AC5E-65D9C23FBD8B','Centrogenyidae',96)
,('1F761C14-3A8B-454F-B7CB-6604B8C91505','Amarsipidae',17)
,('23533BD0-4A5E-441F-8D20-66F87F952E3F','Luciocephalidae',279)
,('C0A9037E-7899-42F4-83D0-670FD2EFB2DB','Xiphiidae',516)
,('E4FB1DDF-EBE9-49AD-96F1-678B8B6C4022','Scytalinidae',457)
,('51A408F6-C3D1-427A-AD0E-67C448EF5BD9','Muraenesocidae',311)
,('A65B4985-0244-493C-BABD-67C8387EFCA0','Rajidae',428)
,('AE08C031-0F05-4CD3-BF58-6886E414588A','Berycidae',71)
,('749AD9BF-FCD4-485A-9DC0-68C471582B84','Polypteridae',402)
,('C8AA8A0D-3E7D-441B-A27A-6954DFCCF7B7','Lamnidae',257)
,('C3114B16-E868-4897-ABF5-6A589E5C9B58','Mastacembelidae',285)
,('C37EEF9D-9079-4AB9-AEC2-6B060E717439','Pentanchidae',372)
,('58A1893A-59BE-426C-B46C-6C2F3D68D46F','Astroblepidae',49)
,('D3141333-A599-4937-90AE-6C62EB202002','Diplomystidae',166)
,('94BDD0A9-73E6-40FC-8C34-6C91E6F1F1F2','Anabantidae',24)
,('AF396416-6471-4325-8EC2-6D5C410D0ADC','Cepolidae',101)
,('9C24C0CE-4BB4-47F4-8295-6D7B8B6FA42B','Clinidae',131)
,('2BD576BB-D6A3-48FC-B9B4-6E7994E0A672','Oneirodidae',342)
,('4D689525-A9DB-4998-925A-6E8CF3E9D63F','Icosteidae',243)
,('D5262554-CC2C-46C1-90A0-6E982BF43282','Pomacentridae',404)
,('3D45096F-9119-4195-9CB8-6EA3209CCCDE','Blenniidae',72)
,('5DA850FD-7DBC-4954-B8F8-702E9029B446','Rachycentridae',426)
,('D7E912F1-34E1-412D-B50B-703E9ABEB1A3','Dentatherinidae',158)
,('44E53991-A767-4974-B9D9-714EFDCD3AFE','Lactariidae',256)
,('1F03E410-77F7-4248-96ED-715F0FEF1EA2','Scomberesocidae',449)
,('AE72459C-6E74-4E7D-A7B7-7174C58FADF7','Bramidae',77)
,('887AD3C5-5E72-4E14-83EA-7248916F5098','Bathyclupeidae',62)
,('D4A12210-0E36-4749-BD6C-7282E7A39289','Terapontidae',489)
,('13833F02-D3D8-43AC-BEA0-72B4FCD9EB16','Eleotridae',176)
,('67B3E272-C380-47DA-A266-72D3D5CA4D51','Draconettidae',169)
,('3939D88D-C06C-406D-8179-72E712FB3363','Helostomatidae',222)
,('2255FFCE-4214-4629-9E87-73B3F0F30171','Mochokidae',299)
,('2480C980-04C9-499F-8A80-742B8C6B22BF','Plotosidae',395)
,('D206F81D-B39A-4334-AD4E-74D7C6BF284C','Elassomatidae',173)
,('676AD92B-A264-4F01-B10C-751B65D40275','Nomeidae',328)
,('B402B88B-B3CF-41B3-BAF2-760526B63C76','Melanonidae',291)
,('26FB0B60-7149-45F7-A5C2-760F46333B2E','Myrocongridae',316)
,('8B463A23-2C28-46A6-920D-76502F449458','Platycephalidae',388)
,('C35B87CC-9666-465A-B971-76A3B49563DB','Bathylagidae',64)
,('79C0F8A9-F6AD-4ED2-8FBB-76A7824D95DC','Plesiobatidae',392)
,('03FE2000-10FC-4F9F-BFB3-7712A98B8CF9','Carangidae',87)
,('D8C82EA7-E340-466B-9EEA-7728D4BEE232','Creediidae',143)
,('B0FA7C6F-ABDB-4215-B6F4-780BBE57DABD','Scopelarchidae',453)
,('ECF6D775-5E12-4DFA-885A-793327A07000','Malapteruridae',284)
,('63B59B7D-FE3A-4A41-8D36-7936CEEFBEAA','Bothidae',73)
,('36A6A825-3BC4-4B88-ABE6-794739075ED7','Hemiramphidae',225)
,('8DE0BF57-352A-453B-8EF6-798D61F0964C','Urolophidae',512)
,('BC7D3A71-D3AF-4B87-BC3D-79920FDE3A88','Anomalopidae',29)
,('1DBD7500-4F85-4DC3-B190-79C239772253','Lophichthyidae',274)
,('7D3074CC-B9B6-431F-8BCE-79E472B089F7','Latridae',260)
,('9D647BB5-185C-4AB1-A0F6-7A8C71DB0096','Retropinnidae',430)
,('29AF363F-8EF4-42D6-9516-7AF641DA15B9','Pseudotriakidae',420)
,('ADB4EE4D-6BFF-497A-A92A-7B3E24C4BC4C','Gymnarchidae',214)
,('5001333E-C09A-4EA6-8CD6-7BABD0FABA12','Monocentridae',302)
,('1922E842-89D1-4F3C-8636-7C2E5B6A5997','Scatophagidae',444)
,('423348B8-B3ED-4418-B54E-7D0487F4CDD5','Muraenidae',312)
,('48613E8C-CD06-4C3B-9AA9-7D401631C800','Nemipteridae',323)
,('8725854F-E14A-42C7-B0EC-7D6B3617EE1E','Harpagiferidae',220)
,('AA0CB957-CC87-4A49-9B39-7D7EAC32B1EE','Evermannellidae',190)
,('6DCCDAE9-C42C-44D4-B0FE-7E4167517FA4','Caproidae',85)
,('0BD8FA99-AF48-4092-B0C5-7E91CF650231','Lophiidae',275)
,('09D065C4-B08B-4D04-909A-7EE4BA03A554','Lepidogalaxiidae',263)
,('D5E1BA7D-FBD7-4B1E-A6CF-807B2946B6D9','Triacanthidae',500)
,('8377E2B0-5F37-4C0B-A4D4-80ADFB597054','Balitoridae',59)
,('696DE492-5686-4083-8687-80E0F6CF5AD8','Scorpaenidae',455)
,('5F6FA01D-84E7-43A8-A252-82110B49C1A5','Leptochariidae',267)
,('C4B6B154-DDCC-4515-8B6D-832CE5E0BD27','Elopidae',177)
,('6951FE03-B0EA-443A-AF53-835CFEF43391','Clupeidae',132)
,('B89D3F5B-334C-4759-B8D1-8380C1E0307A','Inermiidae',246)
,('7FF118E9-56F5-467C-AAE4-83C566591638','Gibberichthyidae',201)
,('9A09D254-C6DE-427F-B6D0-83FA4B2CC60C','Psettodidae',414)
,('97EB4E05-6B91-48B3-8E56-85EB77BC49BD','Priacanthidae',407)
,('87AC7CD7-3347-40DA-BB35-8607CEBD5AD7','Parascylliidae',364)
,('FD7DDA4E-3C2E-41B2-8022-866AC5C4E025','Sternoptychidae',475)
,('E80D8314-D5BD-4CF0-A3EA-86B1A0648C9F','Cryptacanthodidae',145)
,('6EECF3BC-2051-42FB-B387-86E718A48EBC','Ereuniidae',185)
,('104F0D38-3EC2-4FA4-B7D9-872F7106B136','Cobitidae',133)
,('F9B01740-C557-4514-86D0-8790C4C8B146','Bembridae',70)
,('A38EBCC4-EA11-4249-BAA5-87EE53312780','Polyprionidae',401)
,('A1BBE28B-924A-434C-8059-8B6C7C2EFC2C','Scaridae',443)
,('AF264FA9-C9F7-4ADA-AA7B-8BC445DDF2B3','Nettastomatidae',327)
,('1E3A8A9B-45BC-40FF-9988-8C8B6E3055AD','Zanclidae',517)
,('A50C88E5-66F3-4C8F-989A-8CEDEF625E2E','Pholidae',381)
,('2425576C-2264-42C2-A59C-8D5F5BA240A4','Melamphaidae',289)
,('922F4D73-FC6A-471C-840B-8D6681FFAB87','Emmelichthyidae',179)
,('64A3FF28-EC4D-4F8C-B964-8E1D4AA4B861','Chiasmodontidae',118)
,('3F3554F2-3939-48F9-8698-8E5FC6BB1044','Caristiidae',90)
,('A550E127-8CB1-41D5-BF16-8E90180C2E46','Xenisthmidae',515)
,('40605545-00AF-455D-8868-8F1546D3DB72','Centrarchidae',94)
,('D313AA5A-AA3F-444C-9816-8F2B1DCC643D','Haemulidae',218)
,('0F8E52D7-F460-4649-ABE3-8F53C25C3C06','Thaumatichthyidae',494)
,('84573AB3-91DB-452F-9B97-8F68269262BA','Cyprinodontidae',153)
,('863376EA-CAB7-4D5B-909D-8F6ADD73565C','Pimelodidae',386)
,('A59E9276-E574-421C-9DA9-901DDEB076A6','Squatinidae',472)
,('C5D26B9E-A032-40C6-932A-90C4F760C58D','Clariidae',130)
,('4850943F-AAC0-4724-8EB6-91BE194626DC','Balistidae',58)
,('B7C0539D-E378-4E68-9B44-91D3D2DED806','Hexanchidae',234)
,('8CA6F1ED-FA12-47B4-B70A-9200B9F7D698','Setarchidae',461)
,('5B389173-6BD7-4088-8F83-9238CCA3DC23','Soleidae',466)
,('B9C16949-F8C4-46E0-A1FB-92B12FFD031B','Giganturidae',203)
,('3A1100D2-9C12-475B-97ED-92C66269B70A','Catostomidae',91)
,('B23BF536-E0E8-4706-BF9C-92DE92B851C6','Erethistidae',184)
,('7E306AB7-ACE4-4706-B5FB-936F81DD9F50','Nandidae',318)
,('E383A77F-3863-400E-88B4-9389D6747063','Cetopsidae',105)
,('889D7FCC-B1D9-492F-81EC-94135C037CC0','Galaxiidae',195)
,('DED836AD-D108-402B-97C8-94A98396D57F','Chaetodontidae',109)
,('DF1903A1-8305-4A9E-9812-94EA943E86E0','Bregmacerotidae',78)
,('6CEB5A29-62B8-4E78-BEB9-95CC67D22909','Chaunacidae',116)
,('33080C7A-BBE7-4FDA-A5FA-96A724654FD5','Leptoscopidae',269)
,('330036CE-4137-4FAA-A50A-96BEECEF41AC','Bovichtidae',74)
,('DE4844CA-C5C8-40EA-BF61-97535FB3AC2C','Anoplopomatidae',31)
,('6F76623E-DE1C-4C6C-94D6-977BAEB87A99','Zenionidae',521)
,('3CC6DD7C-64A9-4F78-B470-978E90FEA439','Scombropidae',452)
,('A7E0574E-6E10-47A7-AF9B-983AE6A97743','Trichodontidae',504)
,('6AF62259-6E57-4D99-891A-98BE7F79DFA3','Crenuchidae',144)
,('13672C91-8B97-4EF9-8E7F-9954CE86596C','Alopiidae',16)
,('AEC946DD-6237-461E-B50D-996DF2C61CAA','Zaniolepididae',518)
,('1814FA6C-D37D-44AE-AC91-9A46CCBF6A83','Hemiscylliidae',226)
,('DD2680C3-0F24-4451-83C5-9B8E1A422DE0','Lethrinidae',270)
,('2674F833-02B1-4437-BAF2-9C54FC9902FA','Grammatidae',212)
,('5EB81B02-4E34-4228-B07B-9CC09B70116E','Champsodontidae',110)
,('8176B024-5297-4158-8363-9D39C9CD483A','Polynemidae',399)
,('2980FE3D-B5C0-443F-A8F4-9DE0AFD9E3A5','Platytroctidae',389)
,('7221E9ED-899A-48EB-8947-9DE1A9A8EF59','Scophthalmidae',454)
,('32529DAE-DF4B-4CE8-BB06-9E260B35DCB9','Omosudidae',341)
,('F90F7CE7-6EAE-48E1-9616-9E69DED47D06','Carcharhinidae',89)
,('402C9416-EFAD-4BF8-96C2-9E9BB5959EAC','Pholidichthyidae',382)
,('338BFB26-A2C0-4216-BDE4-9ED8587996FE','Moronidae',308)
,('E553CC91-7EAD-45A0-8704-9F375BDE7D6D','Serranidae',459)
,('4CA8E431-D9E1-4C0B-8BDD-9F46182409FD','Potamotrygonidae',406)
,('76A2D71F-1D4B-49A1-B12C-9F91162F2F02','Tetraodontidae',492)
,('AB7C92A6-593C-4B03-925E-A0D2EADEEB18','Parascorpididae',363)
,('D8E368AF-2E60-4035-BD87-A0F466536963','Heterenchelyidae',230)
,('21F4D7DE-F00A-4895-A9E4-A191AD9E6B13','Cetomimidae',104)
,('792C5B6C-7299-44D1-91C7-A1CF990E5449','Abyssocottidae',1)
,('6D85B19D-B2A9-4FF6-8079-A29F42CE9243','Mormyridae',307)
,('B11CBB93-A881-4855-B2C4-A32802AE2953','Symphysanodontidae',482)
,('A0769C11-9E9E-4251-82DB-A33594097450','Diretmidae',167)
,('8556B38E-40D2-4E10-BC54-A3CFBD8103E1','Sciaenidae',447)
,('5A7AA867-F540-4965-A1EF-A502E192C2B7','Batrachoididae',67)
,('02EE6633-02A0-4C04-9AF2-A57D87F93AC1','Tetrarogidae',493)
,('91C1C9D4-3025-414A-929C-A6A7A4FD0DD3','Chlamydoselachidae',123)
,('17EE54F3-4C3F-45DF-880C-A70A73F42E72','Schindleriidae',446)
,('EE56166A-DC3E-4150-8B2C-A747CFEBF3FA','Ostracoberycidae',354)
,('9D2613FF-D6CE-42E8-B9A4-A778A9E580FE','Aphredoderidae',35)
,('17ED5E03-23BA-4F12-973C-AA2D539E3FB9','Moringuidae',306)
,('679CA625-1EBF-4834-B644-AA4ED918FA2E','Gymnuridae',216)
,('43C53B5E-9CAE-48BE-AFDD-AA6480CA2343','Pomacanthidae',403)
,('282A6DA6-2F51-46D3-920C-AA6D1D9FC549','Protopteridae',413)
,('D47AAB78-12AE-47FF-B372-AAD4151420C2','Tetragonuridae',491)
,('EF5067E3-2180-4F90-B655-AB32FB9237B0','Myxinidae',317)
,('8FE2F777-D464-4DB3-AF24-ABCB6FD5E71E','Pseudomugilidae',418)
,('B06D4414-68BC-4129-8A44-AC96029098AB','Paralepididae',361)
,('10E42ADC-7FB7-49C5-BF63-AD2631F861E5','Polymixiidae',398)
,('58F97163-A149-4995-8623-AE3562E8A043','Enoplosidae',181)
,('66F6E067-D437-410A-BE0E-AF428C86A6FA','Fundulidae',193)
,('A0EED109-A630-49AB-8714-AFD6E80DCF19','Bathydraconidae',63)
,('39046DED-5C0C-451E-B4AA-AFF6D0561E06','Gonostomatidae',210)
,('8CB34EF3-3171-43A0-B147-B0082A039D78','Trachichthyidae',497)
,('59D7DC13-E837-4BFE-98CB-B08D81E703F5','Sisoridae',465)
,('660A4F2C-5DF8-4608-A953-B119619CF8F6','Samaridae',442)
,('7ED6EBDF-C6AB-470E-986A-B16117DCD984','Normanichthyidae',329)
,('33AD1E22-BAA2-42BC-A080-B1C52F4A848B','Schilbeidae',445)
,('AFB7622B-E068-493B-9A42-B2A9915938B8','Anablepidae',25)
,('96C1DB60-185E-40E0-BAC2-B2E329B98A52','Apistidae',37)
,('72B8BA53-0540-411B-B107-B2E3FD10E8CB','Phallostethidae',380)
,('7B63A608-E183-4D69-9806-B39AC309B3AC','Chanidae',111)
,('5CE5C246-21A2-405D-A4B6-B4070A647815','Sundasalangidae',481)
,('1A3A0D1B-0BA1-48DE-97E8-B4DD89E68127','Diceratiidae',161)
,('712CD998-AA5A-47AE-9A8C-B51BC98D9479','Neoceratiidae',324)
,('B4165394-FBD9-4833-9861-B57DC7BD624D','Ogcocephalidae',339)
,('A37E3A95-E0B8-47F7-91C6-B63A45F9B3FA','Apogonidae',41)
,('902A8BD2-76B1-4DC4-B4F1-B646330F8A88','Melanotaeniidae',292)
,('B2697299-4D07-427C-84B0-B6DDD1F3EE68','Aphyonidae',36)
,('9AFA40ED-2E3F-4C5D-A222-B773F53F6C25','Ginglymostomatidae',204)
,('9AB5DBEE-F8A5-442E-A514-B82C95AB34A5','Ptilichthyidae',425)
,('63E8C24B-CF58-482A-9FDF-B88A1D31BF9A','Ariidae',44)
,('AFBE347F-CE15-4BB4-9BC0-B8F1A18416BE','Caesionidae',80)
,('A3E23B62-B1BF-4D7D-85E4-BA4584470957','Sternopygidae',476)
,('BF1B7062-0E9B-46D5-8CA3-BA50D4159CAA','Percopsidae',377)
,('22AF14B2-3B25-469C-AB41-BAE734730D2A','Echinorhinidae',172)
,('0A315F0F-8A9A-43C9-BDFD-BAEC8A9D0B5B','Echeneidae',171)
,('3FF3877C-DCFF-4F7B-8358-BB0CE261E85D','Ageneiosidae',9)
,('C0267383-FA22-4E5A-8857-BB7E02FE7467','Bathylutichthyidae',65)
,('4236A8F0-2948-40F1-8C6F-BBD51F6C0500','Trichomycteridae',505)
,('58693200-E008-4F10-B5F0-BBDACB2A84A7','Aploactinidae',38)
,('64E02E92-4AF6-4B97-BD57-BC2C5F746260','Centracanthidae',93)
,('3CD0CB3D-F7AF-4E47-907D-BC7D069D9B5F','Phractolaemidae',384)
,('FD90D739-DEE3-46C6-94EC-BCAC2FC4885D','Triacanthodidae',501)
,('25583287-100F-4548-B4DD-BCF9319A051D','Pegasidae',369)
,('85161F2C-B24C-4FCA-8A46-BD0366B436C2','Ophichthidae',343)
,('96712F01-D29D-40A5-8DC6-BD18A895AA89','Ceratodontidae',103)
,('2632797A-0178-4F3B-BF20-BD2A5D9712FD','Siganidae',462)
,('E82ED879-EB91-4319-9F01-BD2A99A6AE6C','Opisthoproctidae',345)
,('16FC3331-4948-444E-85B5-BDAA5E0FC8EA','Chironemidae',122)
,('B3459E62-B472-4DA3-BD1F-BDB9C4D2489D','Triodontidae',508)
,('BA09CF1B-8B65-4B16-A9F8-BDBC12CBFD58','Epigonidae',183)
,('0261FAF0-8FDE-4AF2-BD14-BE665B2FFCDB','Achiridae',4)
,('043B76E6-9C7D-4175-9014-BE74D55299CD','Pseudopimelodidae',419)
,('9653B24E-E76D-43C5-8D06-BEDAA51CCB70','Malacanthidae',283)
,('076F7EE3-AC95-4753-8042-BF7DE09A69EB','Zaproridae',519)
,('545EC499-3D13-42CA-BF21-C000D2387928','Scoloplacidae',448)
,('F043FF57-E94F-4872-915C-C064A743CFC3','Pseudotrichonotidae',421)
,('FDE040EA-A3E1-4280-AFDA-C1D8D7111790','Uranoscopidae',511)
,('80DD5A6E-6BB0-48BF-9E73-C2B450DB2608','Myliobatidae',315)
,('A0FE94E8-3509-4BD1-982A-C3C83F0E19A0','Erythrinidae',186)
,('197A3047-EB45-42F4-8219-C43F2E96040E','Chaenopsidae',108)
,('81258DF7-8F03-4C77-960D-C5AD2A04C591','Moridae',305)
,('E69B0745-C563-403D-BC30-C5DBA87E5705','Lobotidae',273)
,('A2BB9792-4789-4D92-BEC3-C64E85C5982E','Zoarcidae',522)
,('A20069D7-F170-4CE1-8F1C-C663557D1033','Acropomatidae',7)
,('46F1F40D-BCFA-4D62-BA89-C6B501B2EFA7','Orectolobidae',348)
,('4E464819-5B8F-4014-BE2C-C78EAF17105E','Auchenipteridae',53)
,('706537FA-7E42-4B65-809B-C79DCD8D1C2B','Melanocetidae',290)
,('24534C04-01D0-41AD-86E6-C7AA4D17CECF','Trichiuridae',503)
,('57B90402-347F-46ED-AEF4-C7ECF92232C8','Pangasiidae',356)
,('2E907141-4CAD-482A-9CD1-C83637594833','Citharinidae',129)
,('45EEFEF5-C91F-43EA-B5B1-C8444D71635B','Radiicephalidae',427)
,('6A0273C2-61F0-4B6D-A681-C847EA1E1BC1','Pomatomidae',405)
,('5B6573E4-11A0-45BB-ABDE-C8D4AE93AB54','Lebiasinidae',261)
,('D6EC044D-A1DD-42CE-80BF-C8E5E23BF995','Paraulopidae',365)
,('D46407EE-96D4-491A-8F1C-CA0B8C22D930','Alepisauridae',13)
,('8C619505-B7E2-4381-842B-CA762C94A1BA','Menidae',293)
,('04BA8DAB-9030-4B9E-8536-CAC72314E6B6','Percidae',374)
,('37FE3206-4182-4EC0-ABCE-CBC587B76C58','Arripidae',46)
,('7287F61E-E052-4F60-A2DC-CBE0389C781C','Linophrynidae',271)
,('EB699651-A1D9-4218-8B11-CCBEBE571E06','Curimatidae',147)
,('09CA2DD5-ED94-4EB8-B040-CD744028313D','Artedidraconidae',47)
,('79C7F215-5661-4DC7-8BDD-CDA9DFCC6461','Parazenidae',366)
,('D4C5E0A1-4A69-43A6-A6BF-CDD0B3599663','Aplocheilidae',39)
,('E7074262-1BD5-4C40-B8B1-CDFBE7EA942E','Hemiodontidae',224)
,('A828124A-8C6C-4B27-851D-CF2EB879FFF2','Anguillidae',28)
,('9D3E9423-5418-446A-8919-CFA7E4E3CD30','Bathymasteridae',66)
,('2A4FFA35-CFEB-4890-AA3D-CFD6CECB69CA','Amphiliidae',23)
,('ADAB4021-A5F1-480F-A458-D042FB8DE491','Achiropsettidae',5)
,('66ADB53B-C23E-48EF-9AC3-D1598E07EA15','Atherinopsidae',52)
,('5DE29549-5EE8-466E-B8B2-D2128851BF98','Anarhichadidae',27)
,('F49FAEF0-1444-42A8-B8B0-D315172686AE','Gobiidae',208)
,('ABB05EBF-B711-402F-B043-D3903665359C','Odontaspididae',337)
,('3EB6CDF6-2C5B-4307-BEAE-D39AA8E1B982','Cyematidae',149)
,('579A2FBD-DA5F-4263-BC8C-D47C446B670C','Myctophidae',314)
,('A107E831-F997-4BE1-AFA3-D498EF74BBCF','Saccopharyngidae',439)
,('AECD61F6-C4C9-48F2-9025-D53723DF132D','Paralichthyidae',362)
,('132675BD-7BD5-4830-A73B-D57E94C6EF47','Anacanthobatidae',26)
,('E061C300-CD06-44D3-844A-D5B9289B776B','Rhinobatidae',434)
,('65F2A2C1-17F7-445F-8B28-D5BDC1730360','Glaucosomatidae',205)
,('4BB446DD-958D-4116-86D9-D5DE119C91BF','Sillaginidae',463)
,('811D917B-1067-40BF-BF6C-D60E2D78E51E','Anotopteridae',33)
,('3D85368A-C134-4914-B7CC-D62ED318D67C','Callionymidae',83)
,('75B697A2-2DC7-45F2-833F-D6605ED01845','Psychrolutidae',423)
,('B25CD2E4-D80D-46AB-B5CE-D74256382A3E','Belonidae',69)
,('5EEC80A6-BF0B-4E66-A51F-D7F2794306FA','Cynodontidae',150)
,('F00A7354-0C0D-41E2-84F3-D80BE6D47654','Centrolophidae',97)
,('7FBC7B56-6615-4DC8-AF5D-D84250F28530','Dalatiidae',156)
,('46C06763-AF95-44AD-B987-D8D86CCADEB8','Stichaeidae',477)
,('BE78CCDA-DC55-439B-94CC-D9FAC83078D7','Mullidae',310)
,('D2DDA6BA-E417-4E78-A0FB-DA75CAF624A9','Percichthyidae',373)
,('1D8A8C93-1E8C-4ECE-B31D-DA7C4609AE26','Osmeridae',350)
,('D801AD65-AFE9-4D05-9707-DA99C00F064C','Lepidosirenidae',264)
,('D5DD46FF-B899-45BD-B1F8-DAD7F959BACD','Opistognathidae',346)
,('FFB4F37F-3128-4F74-8D87-DB256673FCFB','Stylephoridae',480)
,('4A94E5D4-9157-4A32-890D-DB4C160406AA','Channichthyidae',112)
,('98900763-97D9-4C07-A28D-DBC81714C641','Sphyrnidae',470)
,('CDD6D6E9-F02C-414B-B41C-DBED4286BFD9','Kyphosidae',253)
,('6D987510-8685-4F4F-A1E7-DC0DA23C1E31','Eurypharyngidae',189)
,('13E73747-014C-4552-BDB2-DC116D6E432C','Dasyatidae',157)
,('E1158A8F-0ECC-41D2-981A-DC41C13E4222','Profundulidae',411)
,('0029256B-F618-4D4D-B1B3-DD7FF2FF8FAB','Hemigaleidae',223)
,('8D322059-E08C-43B1-BCD9-DDD99F659E29','Megalomycteridae',287)
,('F444C6BF-44A7-4419-8624-DF152DAD37D8','Petromyzontidae',379)
,('9AF460CA-BC5E-408E-9720-DF5284667BAE','Ammodytidae',22)
,('5A397367-CC1A-4593-87F7-DF8629BBFC15','Rhamphocottidae',432)
,('57653C9D-0569-43C1-AA60-DFAFE8737B11','Mitsukurinidae',298)
,('507D9A9F-0284-4B37-BBEB-E0D28FABE5F5','Anoplogastridae',30)
,('B17E0B88-AEF0-4EA1-9D87-E12D7ED75416','Valenciidae',513)
,('759CC2DB-9461-41AE-AE97-E2EDA7040BB3','Chilodontidae',119)
,('04E43D91-BA3B-4A4F-AD8E-E3453C27BE7E','Drepaneidae',170)
,('1AAAE4BA-0BB9-4A67-A4AC-E3F2D63A17D1','Esocidae',187)
,('5D6073E4-091C-49CD-AAE6-E41617F3BB5B','Hypoptychidae',242)
,('C68A7807-D350-4B04-8797-E47933DB143E','Cyclopteridae',148)
,('0D3F3EB6-0D82-436F-9F7B-E50C857620DB','Istiophoridae',248)
,('4DA4EFA9-FFC8-4D36-BEF6-E5EFE0948097','Parakysidae',360)
,('F3DB5709-1EE5-40E3-9A29-E6909AFD671E','Macrouridae',282)
,('FF536072-713B-4350-B4F2-E71F866825A9','Centrophoridae',98)
,('CEE8ED62-0164-4BD4-9439-E7643F823013','Pataecidae',368)
,('F140739C-F186-4485-B2C4-E94F4318E37C','Scombrolabracidae',451)
,('F4305B10-4414-4F5E-9993-E95110187027','Poeciliidae',396)
,('6C867463-8895-40D5-BF81-EA86B0E7F9EA','Agonidae',10)
,('AD4570A4-2CD9-4D48-AB3A-EA8B7789416E','Mugilidae',309)
,('4E481F6C-446E-4151-A5FF-EAFA09DEC4CC','Bagridae',57)
,('1676A60E-352B-40D4-8B2E-EBF2014B3B19','Odontobutidae',338)
,('33C6845E-0E03-47C2-8A6B-EC1FC9A395E5','Gasteropelecidae',196)
,('28271A91-1925-4826-9414-EC63DB1E7BDE','Chaudhuriidae',115)
,('809839D3-285E-4E2D-A4C5-EC6993273F22','Liparidae',272)
,('FB6AA617-249B-478F-B6D2-EC7AA5AE6A5B','Ambassidae',18)
,('BAB2FB3D-A3ED-4FF9-91AB-ECBF89EDFAF8','Monodactylidae',303)
,('02326336-E870-4956-B20D-ED117D1F51B8','Cranoglanididae',142)
,('37E9C92B-8122-45F9-9F7B-ED14D5F31816','Telmatherinidae',488)
,('334E2C33-695E-43BA-AF52-EDB2AC2CF1AF','Aspredinidae',48)
,('C3AB3407-415B-4CE4-B3D3-EE7B475DC4FE','Leiognathidae',262)
,('70884107-F707-4014-9E3C-EECE5782A0C4','Syngnathidae',486)
,('740A5592-FA69-4FDB-B3E1-EF7175A20186','Phosichthyidae',383)
,('B3B6FD5A-DB37-4AFA-B94D-EFC7C93C6A5C','Amblyopsidae',20)
,('629C973F-DBBC-44A2-911D-EFE6D059C345','Euclichthyidae',188)
,('9D8BCD9E-60FC-4B1F-9BCE-F0AAF69D0434','Argentinidae',43)
,('0A5C9E94-7BD6-43A3-AF93-F1C88FD4A166','Serrivomeridae',460)
,('5BCA0E49-A488-4FA9-9F3B-F23F34094E29','Pleuronectidae',394)
,('7CBAFEAB-6B52-469B-AC47-F24F5F64C80E','Acipenseridae',6)
,('6E17C2F7-0505-456C-B28B-F25AB1B5D162','Cottocomephoridae',141)
,('4AA829E9-FE1D-47D5-96BA-F2E7E62A410F','Polycentridae',397)
,('1358D250-1D27-4C29-B8E9-F32888C01458','Atherinidae',51)
,('0D66F3EB-B0F8-46F8-97D9-F3424C9F5A04','Megalopidae',288)
,('FD0847E3-54A9-4E8B-9897-F35F1B8A216B','Gempylidae',198)
,('132768A1-24F0-4D4B-8784-F40BE7FB3F72','Pseudochromidae',417)
,('F47E2032-7FE0-48BA-81B9-F60694D8C8C7','Triglidae',507)
,('D83A137B-EC51-4B04-8F69-F8ED716D22F5','Engraulidae',180)
,('C630DF48-B772-4E51-8C34-FA6F9051B471','Pinguipedidae',387)
,('D549C1D9-8A6D-4904-8A62-FA941F59128A','Molidae',300)
,('DBA6B608-AF81-481B-9935-FB0419725AAC','Callorhinchidae',84)
,('827A1634-3FF7-4307-BF84-FB42959D1AC2','Lutjanidae',280)
,('05473723-DE01-49E7-8123-FBD57C962A71','Gigantactinidae',202)
,('A48B7674-9C12-4B11-95FE-FC4F1A3B3416','Kurtidae',252)
,('64065FF7-F8D3-46B1-A505-FDEB09582BB3','Antennariidae',34)
,('65315D63-57CF-4040-B21D-FEA8661E5F77','Brachaeluridae',75)
,('5BEFD243-3716-48C8-9EB5-FEAFB9C4FC5C','Hypopomidae',241)
,('7E21B522-E0D6-43DB-AF9B-FEDEA932677E','Alepocephalidae',14)
,('112BA17C-C956-44BF-BCBA-FF29D41DB263','Leptobramidae',266)
,('4A95BF2E-F713-46CB-BDB2-FFD84CBEEF79','Coiidae',134)
,('5C06B765-C538-4C45-8C98-B9C676288E07','Cichlid',100005) 
,('70DC9966-6353-4F46-9194-CE539A38C160','Arapaimidae',100002)
,('70DC9966-6353-4F41-9194-CE539A38C160','Serrasalmidae',100001)
GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO Country (Country_id, Country_name) VALUES
 ('AA  ','ARUBA')
,('AC  ','ANTIGUA AND BARBUDA')
,('AF  ','AFGHANISTAN')
,('AG  ','ALGERIA')
,('AI  ','ASCENSION ISLAND')
,('AJ  ','AZERBAIJAN')
,('AL  ','ALBANIA')
,('AM  ','ARMENIA')
,('AN  ','ANDORRA')
,('AO  ','ANGOLA')
,('AQ  ','AMERICAN SAMOA')
,('AR  ','ARGENTINA')
,('AS  ','AUSTRALIA')
,('AT  ','ASHMORE AND CARTIER ISLANDS')
,('AU  ','AUSTRIA')
,('AV  ','ANGUILLA')
,('AX  ','ANTIGUA, ST. KITTS, NEVIS, BARBUDA')
,('AY  ','ANTARCTICA')
,('AZ  ','AZORES')
,('BA  ','BAHRAIN')
,('BB  ','BARBADOS')
,('BC  ','BOTSWANA')
,('BD  ','BERMUDA')
,('BE  ','BELGIUM')
,('BF  ','BAHAMAS THE')
,('BG  ','BANGLADESH')
,('BH  ','BELIZE')
,('BK  ','BOSNIA AND HERZEGOVINA')
,('BL  ','BOLIVIA')
,('BM  ','BURMA')
,('BN  ','BENIN')
,('BO  ','BELARUS')
,('BP  ','SOLOMON ISLANDS')
,('BQ  ','NAVASSA ISLAND')
,('BR  ','BRAZIL')
,('BS  ','BASSAS DA INDIA')
,('BT  ','BHUTAN')
,('BU  ','BULGARIA')
,('BV  ','BOUVET ISLAND')
,('BX  ','BRUNEI')
,('BY  ','BURUNDI')
,('BZ  ','BELGIUM AND LUXEMBOURG')
,('CA  ','CANADA')
,('CB  ','CAMBODIA')
,('CC  ','CEUTA AND MELILLA')
,('CD  ','CHAD')
,('CE  ','SRI LANKA')
,('CF  ','CONGO')
,('CG  ','ZAIRE')
,('CH  ','CHINA')
,('CI  ','CHILE')
,('CJ  ','CAYMAN ISLANDS')
,('CK  ','COCOS (KEELING) ISLANDS')
,('CL  ','CAROLINE ISLANDS')
,('CM  ','CAMEROON')
,('CN  ','COMOROS')
,('CO  ','COLOMBIA')
,('CP  ','CANARY ISLANDS')
,('CQ  ','NORTHERN MARIANA ISLANDS')
,('CR  ','CORAL SEA ISLANDS')
,('CS  ','COSTA RICA')
,('CT  ','CENTRAL AFRICAN REPUBLIC')
,('CU  ','CUBA')
,('CV  ','CAPE VERDE')
,('CW  ','COOK ISLANDS')
,('CY  ','CYPRUS')
,('CZ  ','CANTON ISLAND')
,('DA  ','DENMARK')
,('DJ  ','DJIBOUTI')
,('DO  ','DOMINICA')
,('DQ  ','JARVIS ISLAND')
,('DR  ','DOMINICAN REPUBLIC')
,('DY  ','DEMOCRATIC YEMEN')
,('EC  ','ECUADOR')
,('EG  ','EGYPT')
,('EI  ','IRELAND')
,('EK  ','EQUATORIAL GUINEA')
,('EN  ','ESTONIA')
,('ER  ','ERITREA')
,('ES  ','EL SALVADOR')
,('ET  ','ETHIOPIA')
,('EU  ','EUROPA ISLAND')
,('EZ  ','CZECH REPUBLIC')
,('FG  ','FRENCH GUIANA')
,('FI  ','FINLAND')
,('FJ  ','FIJI')
,('FK  ','FALKLAND ISLANDS (ISLAS MALVINAS)')
,('FM  ','MICRONESIA, FEDERATED STATES OF')
,('FO  ','FAROE ISLANDS')
,('FP  ','FRENCH POLYNESIA')
,('FQ  ','BAKER ISLAND')
,('FR  ','FRANCE')
,('FS  ','FRENCH SOUTHERN AND ANTARCTIC LANDS')
,('GA  ','GAMBIA  THE')
,('GB  ','GABON')
,('GG  ','GEORGIA')
,('GH  ','GHANA')
,('GI  ','GIBRALTAR')
,('GJ  ','GRENADA')
,('GK  ','GUERNSEY')
,('GL  ','GREENLAND')
,('GM  ','GERMANY')
,('GO  ','GLORIOSO ISLANDS')
,('GP  ','GUADELOUPE')
,('GQ  ','GUAM')
,('GR  ','GREECE')
,('GT  ','GUATEMALA')
,('GV  ','GUINEA')
,('GY  ','GUYANA')
,('GZ  ','GAZA STRIP')
,('HA  ','HAITI')
,('HK  ','HONG KONG')
,('HM  ','HEARD ISLAND AND MCDONALD ISLANDS')
,('HO  ','HONDURAS')
,('HQ  ','HOWLAND ISLAND')
,('HR  ','CROATIA')
,('HU  ','HUNGARY')
,('IC  ','ICELAND')
,('ID  ','INDONESIA')
,('IM  ','MAN  ISLE OF')
,('IN  ','INDIA')
,('IO  ','BRITISH INDIAN OCEAN TERRITORY')
,('IP  ','CLIPPERTON ISLAND')
,('IR  ','IRAN')
,('IS  ','ISRAEL')
,('IT  ','ITALY')
,('IV  ','COTE D"IVOIRE')
,('IW  ','ISRAEL-JORDAN DMZ')
,('IZ  ','IRAQ')
,('JA  ','JAPAN')
,('JE  ','JERSEY')
,('JM  ','JAMAICA')
,('JN  ','JAN MAYEN')
,('JO  ','JORDAN')
,('JQ  ','JOHNSTON ATOLL')
,('JU  ','JUAN DE NOVA ISLAND')
,('KE  ','KENYA')
,('KG  ','KYRGYZSTAN')
,('KN  ','KOREA, NORTH')
,('KQ  ','KINGMAN REEF')
,('KR  ','KIRIBATI')
,('KS  ','KOREA, SOUTH')
,('KT  ','CHRISTMAS ISLAND')
,('KU  ','KUWAIT')
,('KV  ','KOSOVO')
,('KZ  ','KAZAKHSTAN')
,('LA  ','LAOS')
,('LC  ','ST. LUCIA AND ST. VINCENT')
,('LE  ','LEBANON')
,('LG  ','LATVIA')
,('LH  ','LITHUANIA')
,('LI  ','LIBERIA')
,('LN  ','SOUTHERN LINE ISLANDS')
,('LO  ','SLOVAKIA')
,('LQ  ','PALMYRA ATOLL')
,('LS  ','LIECHTENSTEIN')
,('LT  ','LESOTHO')
,('LU  ','LUXEMBOURG')
,('LY  ','LIBYA')
,('MA  ','MADAGASCAR')
,('MB  ','MARTINIQUE')
,('MC  ','MACAU')
,('MD  ','MOLDOVA')
,('ME  ','MADEIRA')
,('MF  ','MAYOTTE')
,('MG  ','MONGOLIA')
,('MH  ','MONTSERRAT')
,('MI  ','MALAWI')
,('MJ  ','MONTENEGRO')
,('MK  ','MACEDONIA')
,('ML  ','MALI')
,('MM  ','BURMA (MYANMAR)')
,('MN  ','MONACO')
,('MO  ','MOROCCO')
,('MP  ','MAURITIUS')
,('MQ  ','MIDWAY ISLANDS')
,('MR  ','MAURITANIA')
,('MT  ','MALTA')
,('MU  ','OMAN')
,('MV  ','MALDIVES')
,('MW  ','MONTENEGRO')
,('MX  ','MEXICO')
,('MY  ','MALAYSIA')
,('MZ  ','MOZAMBIQUE')
,('NC  ','NEW CALEDONIA')
,('NE  ','NIUE')
,('NF  ','NORFOLK ISLAND')
,('NG  ','NIGER')
,('NH  ','VANUATU')
,('NI  ','NIGERIA')
,('NL  ','NETHERLANDS')
,('NO  ','NORWAY')
,('NP  ','NEPAL')
,('NR  ','NAURU')
,('NS  ','SURINAME')
,('NT  ','NETHERLANDS ANTILLES')
,('NU  ','NICARAGUA')
,('NZ  ','NEW ZEALAND')
,('OD  ','SOUTH SUDAN')
,('OW  ','OCEAN WEATHER STATIONS')
,('PA  ','PARAGUAY')
,('PC  ','PITCAIRN ISLANDS')
,('PE  ','PERU')
,('PF  ','PARACEL ISLANDS')
,('PG  ','SPRATLY ISLANDS')
,('PI  ','PHOENIX ISLANDS')
,('PK  ','PAKISTAN')
,('PL  ','POLAND')
,('PM  ','PANAMA')
,('PN  ','NORTH PACIFIC ISLANDS')
,('PO  ','PORTUGAL')
,('PP  ','PAPUA NEW GUINEA')
,('PS  ','PALAU - TRUST TERRITORY OF THE PACIFIC ISLANDS')
,('PU  ','GUINEA-BISSAU')
,('PZ  ','SOUTH PACIFIC ISLANDS')
,('QA  ','QATAR')
,('RE  ','REUNION AND ASSOCIATED ISLANDS')
,('RI  ','SERBIA')
,('RM  ','MARSHALL ISLANDS')
,('RO  ','ROMANIA')
,('RP  ','PHILIPPINES')
,('RQ  ','PUERTO RICO')
,('RS  ','RUSSIA')
,('RW  ','RWANDA')
,('SA  ','SAUDI ARABIA')
,('SB  ','ST. PIERRE AND MIQUELON')
,('SC  ','ST. KITTS AND NEVIS')
,('SE  ','SEYCHELLES')
,('SF  ','SOUTH AFRICA')
,('SG  ','SENEGAL')
,('SH  ','ST. HELENA')
,('SI  ','SLOVENIA')
,('SK  ','SARAWAK AND SABA')
,('SL  ','SIERRA LEONE')
,('SM  ','SAN MARINO')
,('SN  ','SINGAPORE')
,('SO  ','SOMALIA')
,('SP  ','SPAIN')
,('SR  ','SERBIA')
,('SS  ','ST. MAARTEN')
,('ST  ','ST. LUCIA')
,('SU  ','SUDAN')
,('SV  ','SVALBARD')
,('SW  ','SWEDEN')
,('SX  ','SOUTH GEORGIA AND THE SOUTH SANDWICH ISLANDS')
,('SY  ','SYRIA')
,('SZ  ','SWITZERLAND')
,('TC  ','UNITED ARAB EMIRATES')
,('TD  ','TRINIDAD AND TOBAGO')
,('TE  ','TROMELIN ISLAND')
,('TH  ','THAILAND')
,('TI  ','TAJIKISTAN')
,('TK  ','TURKS AND CAICOS ISLANDS')
,('TL  ','TOKELAU')
,('TN  ','TONGA')
,('TO  ','TOGO')
,('TP  ','SAO TOME AND PRINCIPE')
,('TS  ','TUNISIA')
,('TU  ','TURKEY')
,('TV  ','TUVALU')
,('TW  ','TAIWAN')
,('TX  ','TURKMENISTAN')
,('TZ  ','TANZANIA')
,('UA  ','FORMER USSR (ASIA)')
,('UE  ','FORMER USSR (EUROPE)')
,('UG  ','UGANDA')
,('UK  ','UNITED KINGDOM')
,('UP  ','UKRAINE')
,('US  ','UNITED STATES')
,('UV  ','BURKINA FASO')
,('UY  ','URUGUAY')
,('UZ  ','UZBEKISTAN')
,('VC  ','ST. VINCENT AND THE GRENADINES')
,('VE  ','VENEZUELA')
,('VI  ','VIRGIN ISLANDS (BRITISH)')
,('VM  ','VIETNAM')
,('VQ  ','VIRGIN ISLANDS (U.S.)')
,('VT  ','VATICAN CITY')
,('WA  ','NAMIBIA')
,('WE  ','WEST BANK')
,('WF  ','WALLIS AND FUTUNA')
,('WI  ','WESTERN SAHARA')
,('WQ  ','WAKE ISLAND')
,('WS  ','WESTERN SAMOA')
,('WZ  ','SWAZILAND')
,('YM  ','YEMEN')
,('YU  ','YUGOSLAVIA & FORMER TERRITORY)')
,('YY  ','ST. MARTEEN, ST. EUSTATIUS, AND SABA')
,('ZA  ','ZAMBIA')
,('ZI  ','ZIMBABWE')
,('ZM  ','SAMOA')
,('ZZ  ','ST. MARTIN AND ST. BARTHOLOMEW')
GO
INSERT INTO States (state, country, shift) VALUES
 ('AB','CA',-7)
,('AK','US',-9)
,('AL','US',-4)
,('AR','US',-6)
,('AZ','US',-7)
,('BC','CA',-8)
,('CA','US',-8)
,('CO','US',-7)
,('CT','US',-4)
,('DC','US',-4)
,('DE','US',-4)
,('FL','US',-4)
,('GA','US',-4)
,('HI','US',-10)
,('IA','US',-4)
,('ID','US',-7)
,('IL','US',-6)
,('IN','US',-4)
,('KS','US',-6)
,('KY','US',-4)
,('LA','US',-6)
,('MA','US',-4)
,('MB','CA',-6)
,('MD','US',-4)
,('ME','US',-4)
,('MI','US',-6)
,('MN','US',-4)
,('MO','US',-7)
,('MS','US',0)
,('MT','US',0)
,('NB','CA',-4)
,('NC','US',-4)
,('ND','US',-7)
,('NE','US',-6)
,('NF','CA',-3)
,('NH','US',-4)
,('NJ','US',-4)
,('NM','US',-7)
,('NS','CA',-4)
,('NT','CA',-7)
,('NU','CA',-4)
,('NV','US',-7)
,('NY','US',-4)
,('OH','US',-4)
,('OK','US',-6)
,('ON','CA',-4)
,('OR','US',-7)
,('PA','US',-4)
,('PE','CA',-4)
,('PR','US',-4)
,('QC','CA',-4)
,('RI','US',-4)
,('SC','US',-4)
,('SD','US',-6)
,('SK','CA',-6)
,('TN','US',-4)
,('TX','US',-6)
,('UT','US',-7)
,('VA','US',-4)
,('VT','US',-4)
,('WA','US',-8)
,('WI','US',-6)
,('WV','US',-4)
,('WY','US',-7)
,('YT','CA',-8)
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
INSERT INTO fish (fish_id, fish_name, fish_latin, family_id, fish_type) VALUES
  ('640B5682-00C9-4040-86D8-000291B553AD', 'Dace, Longnose', 'Rhinichthys cataractae', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 4) 
, ('C2E8C307-F470-458B-8CEE-000999277126', 'Darter, Redspot', 'Etheostoma artesiae', '00000000-0000-0000-0000-000000000000', 0) 
, ('B44DC4D4-D30D-4C6B-81FC-00D4A275D93B', 'Chub, Hornyhead', 'Nocomis biguttatus', '00000000-0000-0000-0000-000000000000', 4) 
, ('7947A5B8-04FB-491A-B8FA-00FD34C708C7', 'Sucker, Rustyside', 'Thoburnia hamiltoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('243451AF-E597-4FD9-BCE7-01BA86337D15', 'Sunfish, Bluespotted', 'Enneacanthus gloriosus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D530DFA1-7FA5-4D27-8E09-01C792AD53B4', 'Minnow, Manantial Roundnose', 'Dionda argentosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('8AA087DB-1E90-4D1C-B80B-0225ACEC995D', 'Pikeminnow, Sacramento', 'Ptychocheilus grandis', '00000000-0000-0000-0000-000000000000', 0) 
, ('1FE4468A-D3EA-47B8-99AC-02C08C997D8D', 'Darter, Coosa', 'Etheostoma coosae', '00000000-0000-0000-0000-000000000000', 0) 
, ('C058AFBB-FF2F-4E9E-9FCD-02CCB374B51D', 'Shiner, Scarlet', 'Lythrurus fasciolaris', '00000000-0000-0000-0000-000000000000', 0) 
, ('4DD2B860-E55D-4082-93CC-02F15F05A170', 'Darter, Greenfin', 'Etheostoma chlorobranchium', '00000000-0000-0000-0000-000000000000', 0) 
, ('76E514C4-01C3-4A57-8578-035A8CEF63AD', 'Herring, Lake', 'Coregonus artedi', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('BE3A4835-5FBA-4362-944E-04209C8522E1', 'Stonecat', 'Noturus flavus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('63ACB162-4C2F-48F2-98D7-04A5E51A1C60', 'Darter, Bandfin', 'Etheostoma zonistium', '00000000-0000-0000-0000-000000000000', 0) 
, ('FB10A5CA-DEA9-4851-AB47-04D4C50175AF', 'Redhorse, Golden', 'Moxostoma erythrurum', '00000000-0000-0000-0000-000000000000', 0) 
, ('2CFFB500-3E59-4120-9460-055856E9AC5C', 'Walleye', 'Stizostedion vitreum vitreum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('AFD62E1E-8E7A-43F5-89DF-0582DA9AFBF2', 'Sucker, Lost River', 'Deltistes luxatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('5FD9FAE6-4EEE-43E3-8030-06195C539888', 'Topminnow, Saltmarsh', 'Fundulus jenkinsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('5567F02C-BDAA-47EF-B934-063FBC4898C0', 'Cisco, Bering', 'Coregonus laurettae', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 4) 
, ('029E36F2-B822-4B47-BD7D-0643C5C62810', 'Darter, Mud', 'Etheostoma asprigene', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('47CF7486-B402-43C9-A04A-0662D7632A19', 'Madtom, Neosho', 'Noturus placidus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D50558B1-FC60-4FB8-B77A-0741BBF99886', 'Shad, Threadfin', 'Dorosoma petenense', '00000000-0000-0000-0000-000000000000', 0) 
, ('CB2240E2-7F09-4238-9DD6-07490FD58478', 'Madtom, Scioto', 'Noturus trautmani', '00000000-0000-0000-0000-000000000000', 0) 
, ('D0701517-9D2F-4AB8-8D3F-07579ED9CCE4', 'Darter, Muscadine', 'Percina smithvanizi', '00000000-0000-0000-0000-000000000000', 0) 
, ('750D9989-ABBA-4D2F-8A4F-075AD020D3B6', 'Shiner, Wedgespot', 'Notropis greenei', '00000000-0000-0000-0000-000000000000', 0) 
, ('8A771767-A493-4534-A265-0769BA09C5D9', 'Topminnow, Redface', 'Fundulus rubrifrons', '00000000-0000-0000-0000-000000000000', 0) 
, ('EEA9A1D3-ED9D-499C-9C50-080411E5567D', 'Chub, Flathead', 'Platygobio gracilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('902C7ACE-9218-4E11-8BA6-082B7C269583', 'Inconnu', 'Stenodus nelma', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 0) 
, ('164E3DE5-76BB-4133-B9CE-0861A186B4E3', 'Sunfish, Banded', 'Enneacanthus obesus', '00000000-0000-0000-0000-000000000000', 0) 
, ('CA77794D-DD3A-484F-B643-08D8ED1A0A74', 'Darter, Cherokee', 'Etheostoma scotti', '00000000-0000-0000-0000-000000000000', 0) 
, ('3911B28A-DA7A-4593-B610-099B68CC5ED1', 'Sunfish, Orangespotted', 'Lepomis humilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('7A889EAD-3F79-47BE-9168-09AB24899A4E', 'Fourspine Stickleback', 'Apeltes quadracus', '00000000-0000-0000-0000-000000000000', 0) 
, ('BD24C427-87A3-47C4-AB6B-09DC05C58EBD', 'Gambusia, Pecos', 'Gambusia nobilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('60E271C4-6567-4FD3-A240-0A31EEBB3FDE', 'Darter, Chickasaw', 'Etheostoma cervus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A43B401D-B977-46A5-B444-0AFC8C3DE498', 'Burbot', 'Lota lota', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('2BCA3F1C-25A8-44E5-A039-0B478813EFAA', 'Darter, Bankhead', 'Percina sipsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('8234A715-C944-40BB-92EB-0C5BAF075B57', 'Catfish, Headwater', 'Ictalurus lupus', '00000000-0000-0000-0000-000000000000', 0) 
, ('35929116-8EC7-4A82-A815-0C7F88E37232', 'Darter, Paleback', 'Etheostoma pallididorsum', '00000000-0000-0000-0000-000000000000', 0) 
, ('BAACCD31-DAC3-4A11-B61D-0D3C1AEA103E', 'Topminnow, Lowland', 'Fundulus blairae', '00000000-0000-0000-0000-000000000000', 0) 
, ('86F232A0-0A12-46A6-BA93-0D3E914E9605', 'Minnow, Plains', 'Hybognathus placitus', '00000000-0000-0000-0000-000000000000', 0) 
, ('63F00ADF-79BE-4AD7-9905-0DD6CBF8322E', 'Minnow, Suckermouth', 'Phenacobius mirabilis&#x0D;&#x0A;', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('9FDC7DF8-F188-4CC8-8F6D-0DDEA0937321', 'Darter, Stone', 'Etheostoma derivativum', '00000000-0000-0000-0000-000000000000', 0) 
, ('2460A02D-CD68-435F-BE2A-0F5AA1275DD4', 'Perch, Yellow', 'Perca flavescens', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('CF14FA35-0DC9-4017-BC36-0F621A9B3C6A', 'Shiner, River', 'Notropis blennius', '00000000-0000-0000-0000-000000000000', 0) 
, ('BF24A3D0-0FC4-46F9-8DA6-0F9DB715D1CF', 'Darter, Saddleback', 'Percina vigil', '00000000-0000-0000-0000-000000000000', 0) 
, ('37DD8EFD-50F8-43F8-8854-10503AB2E22F', 'Redhorse, Smallmouth', 'Moxostoma breviceps', '00000000-0000-0000-0000-000000000000', 0) 
, ('92FC15B0-91B3-495C-A867-10A4EB68F500', 'Topminnow, Bayou', 'Fundulus nottii', '00000000-0000-0000-0000-000000000000', 0) 
, ('0EA20CD3-A0E6-4C17-BE63-10BAB8E5502A', 'Sucker, June', 'Chasmistes liorus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('4A73C0F3-BCEF-49A0-8AE6-10D29322568B', 'Gambusia, Big Bend', 'Gambusia gaigei', '00000000-0000-0000-0000-000000000000', 0) 
, ('B3A33573-8BC6-4803-B977-10F673AAD711', 'Trout, Rainbow', 'Oncorhynchus mykiss', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('D9805CF2-2950-4FA4-B5A4-10FBA4FC7B0C', 'Atlantic Stingray', 'Dasyatis sabina', '00000000-0000-0000-0000-000000000000', 0) 
, ('A66964DB-57D8-445E-8832-114767B0CA12', 'Sunfish, Bluebarred Pygmy', 'Elassoma okatie', '00000000-0000-0000-0000-000000000000', 0) 
, ('30750B5B-37B3-485E-B7AB-1187B52D6AD6', 'Shiner, Highfin', 'Notropis altipinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('9FC5BFC8-B9E9-4E84-AB21-11AA297E0DCC', 'Topminnow, Barrens', 'Fundulus julisia', '00000000-0000-0000-0000-000000000000', 0) 
, ('A21B1A2A-01A1-4B5C-A34B-127DBDAAE45F', 'Shiner, Duskystripe', 'Luxilus pilsbryi', '00000000-0000-0000-0000-000000000000', 0) 
, ('5B9A59F5-EA4A-4B6D-813F-128BD51F62D7', 'Chub, Oregon', 'Oregonichthys crameri', '00000000-0000-0000-0000-000000000000', 0) 
, ('11D08194-2EFC-4272-9B1E-136662D9E5BE', 'Sculpin, Prickly', 'Cottus asper', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('7BA8F15A-5ECF-403A-95FF-136EAF3D85E1', 'Dace, Pearl', 'Semotilus margarita', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('1E4580DB-673C-47B6-B12D-141F0CEDACA0', 'Cavefish, Spring', 'Forbesichthys agassizii', '00000000-0000-0000-0000-000000000000', 0) 
, ('0D132774-7858-4153-BE77-1492C1341322', 'Bass, Shadow', 'Ambloplites ariommus', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('7C372D29-8A81-4AE9-979F-151A8A29AC18', 'Minnow, Cutlip', 'Exoglossum maxillingua', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('C7AA19A5-6CBD-4DCA-B458-15219D78CF26', 'Lamprey, American Brook', 'Lethenteron appendix', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('62FFD933-6204-4C4E-B577-1547060CB3DE', 'Pupfish, Owens River', 'Cyprinodon radiosus', '00000000-0000-0000-0000-000000000000', 0) 
, ('91EEBB63-548F-4611-ACF1-154C4F280CF8', 'Topminnow, Russetfin', 'Fundulus escambiae', '00000000-0000-0000-0000-000000000000', 0) 
, ('28E5076A-8C95-49DF-AB34-155C85DAADDA', 'Shiner, Tennessee', 'Notropis leuciodus', '00000000-0000-0000-0000-000000000000', 0) 
, ('18E9B30F-7B78-4E8A-91DB-15C4D6EEE166', 'Dace, Laurel', 'Phoxinus saylori', '00000000-0000-0000-0000-000000000000', 0) 
, ('A2816D4B-0C73-4A55-896E-15E1FDEB599A', 'Dace, Finescale', 'Phoxinus neogaeus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('D87AE8F8-47A8-48A4-9B20-1658D42D286D', 'Madtom, Freckled', 'Noturus nocturnus', '00000000-0000-0000-0000-000000000000', 0) 
, ('54E05E1D-ACFB-4F27-B949-167692BDB00D', 'Pupfish, Comanche Springs', 'Cyprinodon elegans', '00000000-0000-0000-0000-000000000000', 0) 
, ('77A630D3-62E0-4486-84B2-16A3F7BBF700', 'Shiner, Bluenose', 'Pteronotropis welaka', '00000000-0000-0000-0000-000000000000', 0) 
, ('8701BF24-5F53-4534-92E2-16D8DFF061BF', 'Silverside, Waccamaw', 'Menidia extensa', '00000000-0000-0000-0000-000000000000', 0) 
, ('838F173D-49E8-4D73-B82A-16E56B825B71', 'Lamprey, River', 'Lampetra ayresii', '00000000-0000-0000-0000-000000000000', 0) 
, ('03143577-7642-41F2-8B63-179E479A8EFA', 'Shiner, Bluntnose', 'Notropis simus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D5C9A6A2-CF19-4DE8-A05E-18040D0B3E7C', 'Atlantic cod', 'Gadus morhua', '7885FCB8-3FA5-4FB3-8FEE-4B41A72017EA', 0) 
, ('43F99D9C-ED53-4D36-AB00-18552596D2F7', 'Logperch, Texas', 'Percina carbonaria', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('A9F1836A-2750-4BB3-8BB5-1881DB465FAD', 'Shiner, Flagfin', 'Pteronotropis signipinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('68652C06-9F40-4B95-BD3C-1896F2AB2F3D', 'Salmon, Pink', 'Oncorhynchus gorbuscha', '00000000-0000-0000-0000-000000000000', 1) 
, ('771C56BD-09E3-4B58-8C1D-18F27FDE77B1', 'Pupfish, Salt Creek', 'Cyprinodon salinus', '00000000-0000-0000-0000-000000000000', 0) 
, ('8F925042-6C2A-41E6-BAF8-19496913DD23', 'Darter, Blackside Snubnose', 'Etheostoma duryi', '00000000-0000-0000-0000-000000000000', 0) 
, ('B79A813B-BAC8-4D75-8AA5-1992DF489294', 'Shiner, Mountain', 'Lythrurus lirus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B31D6B9A-19BA-4B78-8216-199C9BC28415', 'Warmouth', 'Lepomis gulosus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FCA5094C-4B84-48F2-9865-1A158168D354', 'Chub, Dixie', 'Semotilus thoreauianus', '00000000-0000-0000-0000-000000000000', 0) 
, ('82DB9086-1C0D-4FB7-9664-1A528CD68FFF', 'Dace, Tennessee', 'Phoxinus tennesseensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('30D7B9B1-0A7C-4854-B733-1A95AC2427EE', 'Darter, Brighteye', 'Etheostoma lynceum', '00000000-0000-0000-0000-000000000000', 0) 
, ('03C414CF-C1E4-4221-93AE-1AA7E1EAF68E', 'Sculpin, Klamath Lake', 'Cottus princeps', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('224A936E-6568-4BE1-B0B4-1ABAC0346C0C', 'Madtom, Yellowfin', 'Noturus flavipinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('7ACAF6B6-FF5B-4BB8-969A-1B757E65E966', 'Shiner, Highland', 'Notropis micropteryx', '00000000-0000-0000-0000-000000000000', 0) 
, ('4E3C0943-DC12-4FEC-8977-1B99A9B8A7AB', 'Chub, Utah', 'Gila atraria', '00000000-0000-0000-0000-000000000000', 0) 
, ('936BA07E-531C-48F4-A6FC-1BA351ECD053', 'Darter, Shawnee', 'Etheostoma tecumsehi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D82EB4B2-F488-40C5-9748-1BC42B8E6740', 'Hoodwinker sunfish', 'Mola tecta', 'D549C1D9-8A6D-4904-8A62-FA941F59128A', 0) 
, ('FCEF8147-E288-4C20-85BF-1C79B2F88A63', 'Sucker, Flannelmouth', 'Catostomus latipinnis', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('5672A4D4-35D2-41AF-BD6E-1CED2A3A77D5', 'Chubsucker, Lake', 'Erimyzon sucetta', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('051970D2-1C92-44A2-A908-1D2E100049A8', 'Minnow, Western Silvery', 'Hybognathus argyritis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('C7CE6700-651F-4810-A85E-1D6208A02C98', 'Darter, Yoke', 'Etheostoma juliae', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('587042B7-CF14-4F81-96C1-1D8EA796F123', 'Chub, Thicktail', 'Gila crassicauda', '00000000-0000-0000-0000-000000000000', 0) 
, ('226ED701-A655-41EC-9089-1E1B17FB1B07', 'Darter, Christmas', 'Etheostoma hopkinsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('0F2D0905-3517-4A26-91BD-1F2A41B7D12D', 'Darter, Stripeback', 'Percina notogramma', '00000000-0000-0000-0000-000000000000', 0) 
, ('16ACACAD-3391-44D8-B1A6-1FBE9B51E588', 'Pacific ocean perch', 'Sebastes alutus', '9F5E0B5F-40EC-4565-8FF6-224EC88FBD40', 2) 
, ('E992E16B-583A-4DF4-A8BC-202138B8A1F1', 'Sculpin, Potomac', 'Cottus girardi', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('A25322B7-C7AA-4949-ACBF-20A9FC9360BB', 'Shad, Alabama', 'Alosa alabamae', '6951FE03-B0EA-443A-AF53-835CFEF43391', 0) 
, ('9179BBEB-2050-4877-817C-20CAEB8E519A', 'Darter, Splendid', 'Etheostoma barrenense', '00000000-0000-0000-0000-000000000000', 0) 
, ('A63D18A7-1A98-462B-BAD5-20DB05EF6E9C', 'Trout, Westslope Cutthroat', 'Oncorhynchus clarki lewisi', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('F9A5A5F6-86FE-4B3A-9037-213071F9B4E9', 'Shiner, Kiamichi', 'Notropis ortenburgeri', '00000000-0000-0000-0000-000000000000', 0) 
, ('B8633691-1EEE-4199-A6CE-2158996B4B91', 'Darter, Scaly Sand', 'Ammocrypta vivax', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('D69BF0AA-FA1F-4DD9-98F1-2162A109C00F', 'Darter, Longnose', 'Percina nasuta', '00000000-0000-0000-0000-000000000000', 0) 
, ('3E1A4583-41DA-4288-B909-217EAC0B5581', 'Tilapia', 'Oreochromis niloticus', '5C06B765-C538-4C45-8C98-B9C676288E07', 6) 
, ('A1413418-4656-4721-8421-21E4F9693682', 'Minnow, Roundnose', 'Dionda episcopa', '00000000-0000-0000-0000-000000000000', 0) 
, ('0FB89833-45B4-40B8-A0C4-21F8E3EB5442', 'Bloater', 'Coregonus hoyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('906CC569-0662-45FF-A29F-2273FE0D89F7', 'Stoneroller, Largescale', 'Campostoma oligolepsis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('BC4B2849-A00B-471A-9A38-22994692D17E', 'Darter, Crown', 'Etheostoma corona', '00000000-0000-0000-0000-000000000000', 0) 
, ('4245F7B5-A07E-479F-89D2-22CA2E2A7578', 'Darter, Bluntnose', 'Etheostoma chlorosoma', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('0B871417-5A00-4010-909C-23B231773F7F', 'Shiner, Pinewoods', 'Lythrurus matutinus', '00000000-0000-0000-0000-000000000000', 0) 
, ('74075AEB-9920-4BE2-A82F-240A8C2E839D', 'Mahi-mahi', 'Coryphaena hippurus', 'DD9B5772-0EAE-479F-ACF4-30F6ACDFF449', 1) 
, ('C0997AD5-ECE9-43C1-8B2C-240C51B7DE57', 'Shiner, Cape Fear', 'Notropis mekistocholas', '00000000-0000-0000-0000-000000000000', 0) 
, ('682933D5-8491-4EB7-A3BF-246774F173A9', 'Sucker, Tahoe', 'Catostomus tahoensis', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('ADE8723C-AD6E-44CC-B1E7-248AAD6E691D', 'Bullhead, Yellow', 'Ameiurus natalis', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 1) 
, ('BB557146-B2AF-403D-A033-24B08FDE24FF', 'Chub, Arkansas River Speckled', 'Macrhybopsis tetranema', '00000000-0000-0000-0000-000000000000', 0) 
, ('915A0201-A266-42A0-86C6-24CEF4C91C5D', 'Killifish, Bayou', 'Fundulus pulvereus', '00000000-0000-0000-0000-000000000000', 0) 
, ('C0FE652F-CFA2-4148-94C1-24FC2D7140EB', 'Sturgeon, Lake', 'Acipenser fulvescens', '7CBAFEAB-6B52-469B-AC47-F24F5F64C80E', 3) 
, ('F6373760-69C5-40F9-AD71-252A071D1774', 'Blindcat, Toothless', 'Trogloglanis pattersoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('8F3A2E1F-51A7-4A49-8A4A-2586BA4E4CEA', 'Sucker, Southeastern Blue', 'Cycleptus meridionalis', '00000000-0000-0000-0000-000000000000', 0) 
, ('7D739494-D919-43D6-9B11-25A6B4A28455', 'Sturgeon, Atlantic', 'Acipenser oxyrinchus', '7CBAFEAB-6B52-469B-AC47-F24F5F64C80E', 0) 
, ('B5B6591A-352B-49EF-8B9B-25E34AA122B8', 'Darter, Teardrop', 'Etheostoma barbouri', '00000000-0000-0000-0000-000000000000', 0) 
, ('8B144A9D-D943-4697-BA44-265EA43B251A', 'Bluefish', 'Pomatomus saltatrix', '6A0273C2-61F0-4B6D-A681-C847EA1E1BC1', 3) 
, ('D79B8121-6BB7-4E2B-A2D5-26AAF93A9944', 'Ancistrus patronus', 'Ancistrus patronus', '379EB483-4C8A-4D46-AFB4-5C9FC1BDED69', 0) 
, ('6CDFBB73-58D0-40C6-A623-26F6D3A01417', 'Sucker, Northern Hognose', 'Hypentelium nigricans', '00000000-0000-0000-0000-000000000000', 0) 
, ('C5B76675-286C-459F-912E-26F8F7A0AEA9', 'Shiner, Chihuahua', 'Notropis chihuahua', '00000000-0000-0000-0000-000000000000', 0) 
, ('B0CFFFD5-C607-4336-9972-2730778F0D82', 'Chub, Sicklefin', 'Macrhybopsis meeki', '00000000-0000-0000-0000-000000000000', 0) 
, ('BFF3D62A-EC9F-4955-98BD-27A95E759220', 'Cisco, Shortjaw', 'Coregonus zenithicus', '00000000-0000-0000-0000-000000000000', 1) 
, ('81698ED4-BD98-4637-9EC8-27AD448DCA72', 'Dace, Redside', 'Clinostomus elongatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('810C1F54-68C6-40B6-B400-27C782FE2F78', 'Darter, Blackfin', 'Etheostoma nigripinne', '00000000-0000-0000-0000-000000000000', 0) 
, ('BB86A3D6-0F2C-486C-9917-281786D9F77E', 'Darter, Frecklebelly', 'Percina stictogaster', '00000000-0000-0000-0000-000000000000', 0) 
, ('B28DB303-6614-4637-B6D7-28915518EF7E', 'Hogchoker', 'Trinectes maculatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('4234176D-78D2-4D3F-8360-28E77CA261CC', 'Sucker, Robust redhorse', 'Moxostoma robustum', '00000000-0000-0000-0000-000000000000', 0) 
, ('0EEE9065-E2BC-4708-9114-2951CE55F75F', 'Gambusia, Tex-Mex', 'Gambusia speciosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('ACE02736-1C86-4522-AE59-299575EA4A1B', 'Madtom, Speckled', 'Noturus leptacanthus', '00000000-0000-0000-0000-000000000000', 0) 
, ('C79D98B0-55D9-48A6-83AF-29DF01FD3D68', 'Madtom, Broadtail', 'Noturus sp. 2', '00000000-0000-0000-0000-000000000000', 0) 
, ('FC9C3356-7A07-45FA-A88C-2A8CC303E16C', 'Darter, Brown', 'Etheostoma edwini', '00000000-0000-0000-0000-000000000000', 0) 
, ('520DC643-32C9-4A9C-88F9-2AF55816CA7A', 'Shiner, Sandbar', 'Notropis scepticus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A230DE1D-1298-493B-9956-2B1222C0A5C2', 'Cisco, Deepwater', 'Coregonus johannae', '00000000-0000-0000-0000-000000000000', 4) 
, ('9EDC2E37-BB88-4F83-8139-2B7265373CE5', 'Darter, Cypress', 'Etheostoma proeliare', '00000000-0000-0000-0000-000000000000', 0) 
, ('12B26342-9D0D-4E70-BD06-2B7F0B4386CE', 'Shiner, Pretty', 'Lythrurus bellus', '00000000-0000-0000-0000-000000000000', 0) 
, ('9B851DED-7CA4-47AD-B1F3-2B970B362FEF', 'Darter, Longfin', 'Etheostoma longimanum', '00000000-0000-0000-0000-000000000000', 0) 
, ('817F9239-8C53-439D-9BFE-2BDA8C2078F1', 'Sunfish, Banded Pygmy', 'Elassoma zonatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('7BAFE9B9-C3F5-48E3-A3F3-2BED3D82F520', 'Sculpin, Rough', 'Cottus asperrimus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('F9F7ADAD-EE83-4468-B768-2BFBA450E4A0', 'Darter, Redfin', 'Etheostoma whipplei', '00000000-0000-0000-0000-000000000000', 0) 
, ('369DA27B-8A12-4743-8C20-2C82EC12FE51', 'Madtom, Margined', 'Noturus insignis', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('C063C377-197E-40F7-A072-2C8D2B033119', 'Darter, Redline', 'Etheostoma rufilineatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('19DA6E38-7D82-4BF0-8A0B-2D1D7C44DDB4', 'Minnow, Cheat', 'Pararhinichthys bowersi', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('0153FE03-843E-4CCB-BCEC-2D768853A13B', 'Goby, River', 'Awaous banana', 'F49FAEF0-1444-42A8-B8B0-D315172686AE', 0) 
, ('6B3AD6E6-0D5C-4329-B964-2DF4EE3CE5BD', 'Shiner, Peppered', 'Notropis perpallidus', '00000000-0000-0000-0000-000000000000', 0) 
, ('0844701B-7DF3-4002-B9D6-2DFC9FA6C483', 'Sculpin, Torrent', 'Cottus rhotheus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A35109A0-63BA-4BF5-8A25-2E7E39B74F6E', 'Salmon, Atlantic', 'Salmo salar', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('10F07E8A-D958-4E43-89D8-2EFC7A5EC721', 'Chub, Gila', 'Gila intermedia', '00000000-0000-0000-0000-000000000000', 0) 
, ('CDA7467A-9688-407D-81C9-2F94B3729C75', 'Darter, Stargazing', 'Percina uranidea', '00000000-0000-0000-0000-000000000000', 0) 
, ('BD11CB0B-7734-4BC5-A9BD-3022BA871E69', 'Darter, Yazoo', 'Etheostoma raneyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('19C45110-154D-477F-BA55-309BE16E54CA', 'Splake', 'Salvelinus namaycush X Salvelinus fontinalis', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 17) 
, ('0521D3FE-A10E-496A-9A9E-30B867787845', 'Sturgeon, Alabama', 'Scaphirhynchus suttkusi', '00000000-0000-0000-0000-000000000000', 0) 
, ('A315B8CB-62E7-4381-A0C8-30E679308912', 'Shiner, Whitetail', 'Cyprinella galactura', '00000000-0000-0000-0000-000000000000', 0) 
, ('CC95F272-E644-4D4F-B8F1-310F97BDDE1E', 'Lamprey, Miller Lake', 'Lampetra minima', '00000000-0000-0000-0000-000000000000', 0) 
, ('6AC38B5A-7F70-4D21-878E-315DB5F4A9EC', 'Madtom, Chucky', 'Noturus crypticus', '00000000-0000-0000-0000-000000000000', 0) 
, ('AF655935-FB9B-4A0F-A9CE-3166DFF86D64', 'Sunfish, Redspotted', 'Lepomis miniatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('4EDF2887-CCD4-4CB9-AF37-317B11887AA3', 'Sucker, Modoc', 'Catostomus microps', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('D933407D-E0B9-41E5-9845-318675DFC051', 'Darter, Tuscumbia', 'Etheostoma tuscumbia', '00000000-0000-0000-0000-000000000000', 0) 
, ('43B43FC1-94BC-4472-B5AB-31FCBED6FA18', 'Sea Robins', 'Chelidonichthys spinosus', 'F47E2032-7FE0-48BA-81B9-F60694D8C8C7', 0) 
, ('4B921B67-331E-4FF5-BDDF-3237222217A8', 'Yelloweye rockfish', 'Sebastes ruberrimus', '9F5E0B5F-40EC-4565-8FF6-224EC88FBD40', 0) 
, ('71B290F3-38CB-4088-B723-32805D13C297', 'Darter, Vermilion', 'Etheostoma chermocki', '00000000-0000-0000-0000-000000000000', 0) 
, ('3B68E44B-29C0-4A72-8476-329D82EF7935', 'Shad, Hickory', 'Alosa mediocris', '6951FE03-B0EA-443A-AF53-835CFEF43391', 0) 
, ('7DC0002C-490F-4197-8A3C-32D9C69C36A2', 'Dace, Umpqua', 'Rhinichthys evermanni', '00000000-0000-0000-0000-000000000000', 0) 
, ('1289B656-5836-4884-8EF0-32FE98CB47AE', 'Redhorse, Blacktail', 'Moxostoma poecilurum', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('0352FAAA-E38F-45B6-B838-33030CCA48F5', 'Black Bullhead', 'Ictalurus melas', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 6) 
, ('3912938D-F4F6-47E8-BA01-334C71606D6B', 'Wels catfish', 'Silurus glanis', 'DA8AD379-75CC-4F35-A85C-329AC64A64A5', 1) 
, ('B5E2E354-75C8-4323-8BE7-3400645BA1B7', 'Darter, Snubnose', 'Etheostoma simoterum', '00000000-0000-0000-0000-000000000000', 0) 
, ('DE1157D8-DBB0-4520-9E4F-342AEA28DD69', 'Lamprey, Chestnut', 'Ichthyomyzon castaneus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B41098F2-EC7D-4085-9EF7-342DC460C2F2', 'Salmon, Coho', 'Oncorhynchus kisutch', '00000000-0000-0000-0000-000000000000', 3) 
, ('05A26C63-50D5-407A-B061-345C36B4BA66', 'Madtom, Brindled', 'Noturus miurus', '00000000-0000-0000-0000-000000000000', 0) 
, ('C6B635D7-F7A1-4E6F-8936-3461862855D3', 'Darter, Creole', 'Etheostoma collettei', '00000000-0000-0000-0000-000000000000', 0) 
, ('494044A6-900F-445B-9BA1-34D74BBB620A', 'Sculpin, Deepwater', 'Myoxocephalus thompsoni', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('395A6D2B-126A-484C-8C69-355A721834A4', 'Carp, Silver', 'Hypophthalmichthys molitrix', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 1) 
, ('6A0F36F4-089C-451E-A8C1-356662854AF7', 'Madtom, Brown', 'Noturus phaeus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E59B0F4B-7DA8-4C5F-A7E4-358C7C9DE7DC', 'Lamprey, Ohio', 'Ichthyomyzon bdellium', 'F444C6BF-44A7-4419-8624-DF152DAD37D8', 0) 
, ('012F94FA-0798-4D2E-9376-358D0A77B22D', 'Shiner, Palezone', 'Notropis albizonatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('893D5871-6BF1-4159-A302-35A421FA61EE', 'Darter, Rio Grande', 'Etheostoma grahami', '00000000-0000-0000-0000-000000000000', 0) 
, ('8A92E2BC-2277-42D9-B151-365E64C07206', 'Shiner, Red', 'Cyprinella lutrensis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('236FA1B0-7D27-46E8-B31D-36696BAAFF7E', 'Darter, Sharpnose', 'Percina oxyrhynchus', '00000000-0000-0000-0000-000000000000', 0) 
, ('F240E448-1DCF-4B9C-A88C-36CB8512A379', 'Goby, Nopoli Rockclimbing', 'Sicyopterus stimpsoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('E5FEF647-4B4B-4C84-96BF-375FC8A3C2DA', 'Splittail', 'Pogonichthys macrolepidotus', '00000000-0000-0000-0000-000000000000', 0) 
, ('66B62AEC-A9F6-44D9-AB4E-38768D9C3C54', 'Fallfish', 'Semotilus corporalis', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('95C82D2A-015A-4B2F-AF87-3896072B3872', 'Madtom, Carolina', 'Noturus furiosus', '00000000-0000-0000-0000-000000000000', 0) 
, ('F14E808A-C08D-4D6B-A238-38AFB2187385', 'Shad, American', 'Alosa sapidissima', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('9211FE94-4AEF-4F16-BA86-38CF68156909', 'Lamprey, Small black brook', 'Lampetra lamottei', 'F444C6BF-44A7-4419-8624-DF152DAD37D8', 17) 
, ('AB0B7E32-89E4-437F-8275-38F47FB947F2', 'Chub, Redspot', 'Nocomis asper', '00000000-0000-0000-0000-000000000000', 0) 
, ('2C1F2337-5D0B-4EA7-B88C-395FD645C8C2', 'Whitefish, Mountain', 'Prosopium williamsoni', '00000000-0000-0000-0000-000000000000', 1) 
, ('31F707F2-69C4-42C5-909B-39C84CC8C07E', 'Minnow, Devils River', 'Dionda diaboli', '00000000-0000-0000-0000-000000000000', 0) 
, ('5D355550-7509-41B8-981F-39FA8B7E063C', 'Topminnow, Lined', 'Fundulus lineolatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('10FC5867-01F0-4ACA-8DAF-3A02E5D72071', 'Dace, Umatilla', 'Rhinichthys umatilla', '00000000-0000-0000-0000-000000000000', 0) 
, ('22878ABF-7781-40FF-90E1-3A0A6F37D841', 'Minnow, Pugnose', 'Opsopoeodus emiliae', '00000000-0000-0000-0000-000000000000', 0) 
, ('6B3BDB66-AD3F-4940-AC76-3A179CF73C5F', 'Logperch, Blotchside', 'Percina burtoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('39485984-22AA-4594-8358-3A1923B39708', 'Logperch, Southern', 'Percina austroperca', '00000000-0000-0000-0000-000000000000', 0) 
, ('B38FC279-B03C-4570-8101-3A6C8E23EC74', 'Sculpin, Utah Lake', 'Cottus echinatus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('BDE9D19D-87C8-4ACB-AE96-3A9D7335E059', 'Chub, Southern Leatherside', 'Lepidomeda aliciae', '00000000-0000-0000-0000-000000000000', 0) 
, ('949704F5-962F-4A9E-8806-3AC96FCA2095', 'Gambusia, Clear Creek', 'Gambusia heterochir', '00000000-0000-0000-0000-000000000000', 0) 
, ('D1814745-D6C3-4A95-8503-3C6DFB5B8B21', 'Bowfin', 'Amia calva', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 32) 
, ('0C6616BA-2527-4BAD-8154-3CC075E9C08E', 'Southern Flounder', 'Paralichthys lethostigma', 'AECD61F6-C4C9-48F2-9025-D53723DF132D', 0) 
, ('B08240F9-FE4D-4647-BC0D-3CD569A812B7', 'Chub, Slender', 'Erimystax cahni', '00000000-0000-0000-0000-000000000000', 0) 
, ('B1176EFB-CA0F-4CC5-82C7-3D23A450303C', 'Chub, Chihuahua', 'Gila nigrescens', '00000000-0000-0000-0000-000000000000', 0) 
, ('5B6CBB3D-6EC8-4FD1-986C-3E114725FAB1', 'Sunfish, Redear', 'Lepomis microlophus', '40605545-00AF-455D-8868-8F1546D3DB72', 1) 
, ('66938081-D1F8-477D-948F-3E68D4F9878C', 'Darter, Firebelly', 'Etheostoma pyrrhogaster', '00000000-0000-0000-0000-000000000000', 0) 
, ('A8AC01BB-29B0-4CA1-B269-3EB42D0CB000', 'Chub, Gravel', 'Erimystax x-punctata', '00000000-0000-0000-0000-000000000000', 0) 
, ('471593FD-29BA-4BB6-95F9-3FF72B2D162F', 'Shiner, Ouachita', 'Lythrurus snelsoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('78AE447A-2DE5-418A-834E-40C1F3FB23EC', 'Herring, Blueback', 'Alosa aestivalis', '6951FE03-B0EA-443A-AF53-835CFEF43391', 1) 
, ('B001E0A9-1591-4921-A245-40CB51B1EBBD', 'Red drum', 'Sciaenops ocellatus', '8556B38E-40D2-4E10-BC54-A3CFBD8103E1', 0) 
, ('915208F7-6635-4EFE-9AB3-412C137FE028', 'Darter, Gulf', 'Etheostoma swaini', '00000000-0000-0000-0000-000000000000', 0) 
, ('08473256-E634-43FA-A5C8-413319E19A9E', 'Gar, Spotted', 'Lepisosteus oculatus', '65602359-3AC9-4304-9A46-2DC7619DF12C', 0) 
, ('DEED06F4-BD40-4BF7-A14B-414AC97B007F', 'Darter, Swamp', 'Etheostoma fusiforme', '00000000-0000-0000-0000-000000000000', 0) 
, ('15AC3384-E29C-4299-8E00-416CF86774DA', 'Redhorse, Mexican', 'Moxostoma austrinum', '00000000-0000-0000-0000-000000000000', 0) 
, ('F78D3601-0D33-4EAB-A502-419D52A934DD', 'Lamprey, Silver', 'Ichthyomyzon unicuspis', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 16) 
, ('8BE14D25-B0EC-45CF-8211-421490A083D7', 'Pupfish, Quitobaquito', 'Cyprinodon eremus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B75D7D05-1533-4D69-8E13-4217A72A1E73', 'Madtom, Tadpole', 'Noturus gyrinus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('92FEB130-DF68-4447-85DE-4228C08C649D', 'Darter, Rock', 'Etheostoma rupestre', '00000000-0000-0000-0000-000000000000', 0) 
, ('DA06856B-D503-494F-AE22-424920E5CE85', 'Shiner, Dusky', 'Notropis cummingsae', '00000000-0000-0000-0000-000000000000', 0) 
, ('7C11F466-B9E9-4FF2-954F-428216E4ADAB', 'Minnow, Eastern Silvery', 'Hybognathus regius', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('EA7F8732-9E0D-4624-9CDA-42A22C8D1198', 'Cui-ui', 'Chasmistes cujus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('1EFB6318-2EA5-42BB-9B39-42A66C08E148', 'Sucker, Mountain', 'Catostomus platyrhynchus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 2) 
, ('84F06B66-CD5B-42C5-B7E0-4363FFE5754A', 'Shiner, Bluestripe', 'Cyprinella callitaenia', '00000000-0000-0000-0000-000000000000', 0) 
, ('58FC0EFC-3728-4A7E-9622-43C9747078E8', 'Bass, Guadalupe', 'Micropterus treculii', '00000000-0000-0000-0000-000000000000', 0) 
, ('C0C2D30A-7BB5-4426-83EA-43CE743D62D6', 'Shiner, Greenfin', 'Cyprinella chloristia', '00000000-0000-0000-0000-000000000000', 0) 
, ('3F9DE0AF-13F4-4FC0-A871-43E7DE5C5635', 'Chub, Santee', 'Cyprinella zanema', '00000000-0000-0000-0000-000000000000', 0) 
, ('BFD09863-00ED-40FB-B53A-4438EC77C0FA', 'Chub, Spotfin', 'Erimonax monachus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E7C6D803-CB88-4BE2-80D5-44C0200D574C', 'Shiner, Swallowtail', 'Notropis procne', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('6303E3E9-B7E1-497E-9F22-44DDE02B8FB6', 'Shiner, Carmine', 'Notropis percobromus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D59A9A63-DA2F-4AEE-B449-4500E259F8FC', 'Tench', 'Tinca tinca', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 5) 
, ('C600E0F6-5BC0-4AB7-BE5A-452EA1666929', 'Shiner, Steelcolor', 'Cyprinella whipplei', '00000000-0000-0000-0000-000000000000', 0) 
, ('2EFAE94E-E2DC-4B08-9849-45396C576369', 'Darter, Smallscale', 'Etheostoma microlepidum', '00000000-0000-0000-0000-000000000000', 0) 
, ('5E6A42D4-6DF5-4D6D-AF16-453DCCF622CD', 'Madtom, Smoky', 'Noturus baileyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('596DD997-4EFF-4AFE-BC97-454F3C7A3D28', 'Pupfish, Desert', 'Cyprinodon macularius', '00000000-0000-0000-0000-000000000000', 0) 
, ('CD5B1DAE-0F3F-4A1E-86D4-4558384792AF', 'Shiner, Bluntface', 'Cyprinella camura', '00000000-0000-0000-0000-000000000000', 0) 
, ('14C18FF0-2C3D-42CF-A893-46027F628F88', 'Darter, Corrugated', 'Etheostoma basilare', '00000000-0000-0000-0000-000000000000', 0) 
, ('AF9A8753-180B-46AF-A4CB-46519B856782', 'Shiner, Sharpnose', 'Notropis oxyrhynchus', '00000000-0000-0000-0000-000000000000', 0) 
, ('75B1A51D-24E9-4B5D-B389-469323D8431E', 'Minnow, Bullhead', 'Pimephales vigilax', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 32) 
, ('D1EC7C48-0CEC-435F-BFCE-46FC432C7AED', 'Pupfish, White Sands', 'Cyprinodon tularosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('4E2CF5DE-6925-4086-AB76-470269DBE3D4', 'Chub, Headwater', 'Gila nigra', '00000000-0000-0000-0000-000000000000', 0) 
, ('6BF4D8C1-6E90-4555-9A92-4709D9700413', 'Darter, Roanoke', 'Percina roanoka', '00000000-0000-0000-0000-000000000000', 0) 
, ('8EC97B82-0DE8-46B4-A2D3-47182FD82C20', 'Shiner, Highscale', 'Notropis hypsilepis', '00000000-0000-0000-0000-000000000000', 0) 
, ('3775BB10-6DFD-4E1F-BD2C-473625D06A12', 'Minnow, Fathead', 'Pimephales promelas', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('B26A697A-1B1D-4E42-8737-4779044129E0', 'Chub, Humpback', 'Gila cypha', '00000000-0000-0000-0000-000000000000', 0) 
, ('22652451-E0AF-4020-A5F4-47CAC81CCD7B', 'Shiner, Alabama', 'Cyprinella callistia', '00000000-0000-0000-0000-000000000000', 0) 
, ('876208AD-8ED3-4F98-A32A-47E379A7BAD7', 'Tarpon', 'Megalops cyprinoides', '0D66F3EB-B0F8-46F8-97D9-F3424C9F5A04', 0) 
, ('25E877EA-D371-4B1D-9521-4802D35E76E4', 'Darter, Yellowcheek', 'Etheostoma moorei', '00000000-0000-0000-0000-000000000000', 0) 
, ('EAE93BE7-49D9-4BA2-BF4C-480551F2619B', 'Shiner, Bridle', 'Notropis bifrenatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('01D8BB8D-5DFF-4A4B-9C10-4987026DAD60', 'Shiner, Sabine', 'Notropis sabinae', '00000000-0000-0000-0000-000000000000', 0) 
, ('7D6B4D1D-3969-466D-8A59-49F962B5AC51', 'Darter, Piedmont', 'Percina crassa', '00000000-0000-0000-0000-000000000000', 0) 
, ('985263BA-FFBE-430F-BF08-4A3A62635ECA', 'Dace, Mountain Redbelly', 'Phoxinus oreas', '00000000-0000-0000-0000-000000000000', 0) 
, ('C0BA2FFC-03D5-404B-AF8C-4A499595669D', 'Pupfish, Red River', 'Cyprinodon rubrofluviatilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('BDEACBC5-EC1B-447D-98C3-4AC2ABBDD6F8', 'Cavefish, Ozark', 'Amblyopsis rosae', 'B3B6FD5A-DB37-4AFA-B94D-EFC7C93C6A5C', 0) 
, ('68E32BE0-02B1-4203-8E82-4B1E6A6D370F', 'Gar, Florida', 'Lepisosteus platyrhincus', '65602359-3AC9-4304-9A46-2DC7619DF12C', 0) 
, ('F702A188-3012-42C3-9786-4B39E1BB7A3C', 'Darter, Savannah', 'Etheostoma fricksium', '00000000-0000-0000-0000-000000000000', 0) 
, ('21DB49AE-4E31-4F70-9ED0-4B45E785E52C', 'Catfish, Yaqui', 'Ictalurus pricei', '00000000-0000-0000-0000-000000000000', 0) 
, ('E64F1087-51F4-4348-B96C-4B46528A7D0B', 'Darter, Sharphead', 'Etheostoma acuticeps', '00000000-0000-0000-0000-000000000000', 0) 
, ('FF0B1144-127C-49FE-BA6D-4B837EDBA883', 'Darter, Orangethroat', 'Etheostoma spectabile', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('C3218326-60A6-4BE0-98E9-4B9A7CBA69CD', 'Madtom, Caddo', 'Noturus taylori', '00000000-0000-0000-0000-000000000000', 0) 
, ('5E059955-25F9-49C4-926F-4BB08E2CA85B', 'Minnow, Brassy', 'Hybognathus hankinsoni', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('D6BF46F2-9C5A-4F08-8E74-4BC458AC8C77', 'Sunfish, Spring Pygmy', 'Elassoma alabamae', '00000000-0000-0000-0000-000000000000', 0) 
, ('08BB5A98-5131-4B27-A970-4C12DA95A882', 'Bass, Yellow', 'Morone mississippiensis', '338BFB26-A2C0-4216-BDE4-9ED8587996FE', 1) 
, ('4F344C3A-5D0E-4CCA-A8C3-4C3C9D324DCF', 'Pickerel, Chain', 'Esox niger', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('EDCDE019-BBE2-4522-ADDE-4C3D3568CC45', 'Bonytail', 'Gila elegans', '00000000-0000-0000-0000-000000000000', 0) 
, ('6B72E7B4-2935-4537-BD2B-4C6451D9FDC8', 'Trout, Silver', 'Salvelinus agassizii', '00000000-0000-0000-0000-000000000000', 0) 
, ('1179AF61-D044-4ABD-80B1-4C8C3ABABE5E', 'Darter, Least', 'Etheostoma microperca', '00000000-0000-0000-0000-000000000000', 0) 
, ('D4CBE02E-7C76-4A67-8994-4CCF6D9DBD19', 'Rudd', 'Scardinius erythrophthalmus', '00000000-0000-0000-0000-000000000000', 0) 
, ('71164A91-E4BD-4BE0-B880-4CF6509E0EEA', 'Darter, Bluestripe', 'Percina cymatotaenia', '00000000-0000-0000-0000-000000000000', 0) 
, ('80242AB0-B89C-4CF4-9176-4D36502CD4F8', 'Shiner, Blacknose', 'Notropis heterolepis', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('7450CAF8-2FD1-4577-BA2D-4D6C39212E6E', 'Shiner, Blue', 'Cyprinella caerulea', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('FF9C5A04-BE2F-4EC8-A620-4D70B98C6EFF', 'Dace, Desert', 'Eremichthys acros', '00000000-0000-0000-0000-000000000000', 0) 
, ('8014674D-CA30-4E61-8FA2-4D80D94E5F45', 'Sauger', 'Sander canadensis', '00000000-0000-0000-0000-000000000000', 1) 
, ('8CA1B24C-D378-462F-B195-4D9401FD714E', 'Darter, Carolina', 'Etheostoma collis', '00000000-0000-0000-0000-000000000000', 0) 
, ('F532275B-C4C5-434E-9387-4DCEF419DCB6', 'Darter, Slough', 'Etheostoma gracile', '00000000-0000-0000-0000-000000000000', 0) 
, ('B5F6B57E-44E4-409D-ACFC-4E36E3EE068C', 'Pupfish, Amargosa', 'Cyprinodon nevadensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('B11DFC4D-62FA-4238-AB87-4E3E78B632A7', 'Shiner, Bleeding', 'Luxilus zonatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('61FDEC37-9883-4904-AE51-4E47B1466A9C', 'Gulf Pipefish', 'Syngnathus scovelli', '00000000-0000-0000-0000-000000000000', 0) 
, ('01626518-582F-455D-A3CD-4E70ADBE33CA', 'Shiner, Rio Grande', 'Notropis jemezanus', '00000000-0000-0000-0000-000000000000', 0) 
, ('2038693F-D38C-43C8-B0CE-4E96B0F9AF7E', 'Bass, Smallmouth', 'Micropterus dolomieu', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('0F4E18A6-D7A9-4530-BF25-4EDFDCCF7DC2', 'Darter, Strawberry', 'Etheostoma fragi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D8105D76-61FB-473A-A054-4EE0F9CCDF8B', 'Darter, Fringed', 'Etheostoma crossopterum', '00000000-0000-0000-0000-000000000000', 0) 
, ('14471301-DBA0-4C86-9F10-4F1A2791FB70', 'Sucker, Desert', 'Catostomus clarkii', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('BA268683-5E9D-42B7-890A-4F5349EFDCB9', 'Chub, Arroyo', 'Gila orcuttii', '00000000-0000-0000-0000-000000000000', 0) 
, ('3A704D0C-E74D-4F56-9C79-4F60D3D56776', 'Shiner, Bedrock', 'Notropis rupestris', '00000000-0000-0000-0000-000000000000', 0) 
, ('7C04B7CE-FE09-40BC-A029-4FE4BCD2F7BC', 'Sucker, Utah', 'Catostomus ardens', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('B277094B-6C45-4545-9A4A-500D5E377082', 'Mexican Tetra', 'Astyanax mexicanus', 'B75CDFAA-E5A4-41F7-AF64-3A4ABEE7FA27', 0) 
, ('D874395A-1032-48EA-A527-504AE8DB4DC3', 'Whitefish, Bear Lake', 'Prosopium abyssicola', '00000000-0000-0000-0000-000000000000', 0) 
, ('049D2D25-9FCE-4323-972E-5073441368C2', 'Shiner, Texas', 'Notropis amabilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('1860BCAA-D513-43A7-A687-50D35404FAE7', 'Opossum Pipefish', 'Microphis brachyurus', '00000000-0000-0000-0000-000000000000', 0) 
, ('8FB3B846-92E1-4D38-A72E-51545E3CDDF6', 'Topminnow, Plains', 'Fundulus sciadicus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B77FF536-08FA-46B1-ABDE-515B9DF922AF', 'Chub, Umpqua Oregon', 'Oregonichthys kalawatseti', '00000000-0000-0000-0000-000000000000', 0) 
, ('1D5CCCD9-FBB7-4203-91ED-516FF5C907DF', 'Whitefish, Pygmy', 'Prosopium coulterii', '00000000-0000-0000-0000-000000000000', 0) 
, ('407C0D14-4BC4-4241-8B20-518BEF5B1A37', 'Herring, Skipjack', 'Alosa chrysochloris', '6951FE03-B0EA-443A-AF53-835CFEF43391', 4) 
, ('96458B47-C699-4A90-AB7E-5191471AA4EF', 'Darter, Niangua', 'Etheostoma nianguae', '00000000-0000-0000-0000-000000000000', 0) 
, ('55B0BB5A-9859-406A-9108-5206CBE3EFA6', 'Sculpin, Riffle', 'Cottus gulosus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('5AB8E50A-CD84-4070-8006-5223B4302F14', 'Chub, Burrhead', 'Macrhybopsis marconis', '00000000-0000-0000-0000-000000000000', 0) 
, ('A6890C90-B2C9-4268-9606-5300C10B396F', 'Shiner, Rocky', 'Notropis suttkusi', '00000000-0000-0000-0000-000000000000', 0) 
, ('5E5D48AC-411D-4640-ACA2-5300C4F80AA7', 'Pupfish, Santa Cruz', 'Cyprinodon arcuatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('71E02539-546E-4EAE-9257-5312AA705CAF', 'Darter, Seagreen', 'Etheostoma thalassinum', '00000000-0000-0000-0000-000000000000', 0) 
, ('A92FBC42-7674-439A-83BC-532F79612911', 'Redhorse, Notchlip', 'Moxostoma collapsum', '00000000-0000-0000-0000-000000000000', 0) 
, ('477C78F3-806A-4B94-AD62-5364B52AAD16', 'Mosquitofish, Western', 'Gambusia affinis', '00000000-0000-0000-0000-000000000000', 0) 
, ('96CBA96E-9A6F-467A-9150-539FF2027BC2', 'Darter, Turquoise', 'Etheostoma inscriptum', '00000000-0000-0000-0000-000000000000', 0) 
, ('303F4853-A2C8-4E2D-B002-53A5088765FC', 'Darter, Golden', 'Etheostoma denoncourti', '00000000-0000-0000-0000-000000000000', 0) 
, ('B6D6E5F6-CD4F-458A-BF60-53D8D9E79288', 'Stickleback, Threespine', 'Gasterosteus aculeatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('96D71265-6DB5-41F6-B8A6-5457E4A0B9E3', 'Redhorse, Copper', 'Moxostoma hubbsi', '3A1100D2-9C12-475B-97ED-92C66269B70A', 32) 
, ('83405836-B58E-4E0C-85EF-54B13F172675', 'Shiner, Common', 'Luxilus cornutus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('141284A8-2325-40A0-B0F3-55094A982854', 'Darter, Ashy', 'Etheostoma cinereum', '00000000-0000-0000-0000-000000000000', 0) 
, ('E66484E4-5B24-498B-B33C-551A462B7595', 'Carp, Grass', 'Ctenopharyngodon idella', '00000000-0000-0000-0000-000000000000', 1) 
, ('C9A4B366-CD13-4CA7-AB8B-55BD97915CA8', 'Darter, Freckled', 'Percina lenticula', '00000000-0000-0000-0000-000000000000', 0) 
, ('10F72DFA-D057-42D7-8B81-55F1DA0656CA', 'Snail Bullhead', 'Ameiurus brunneus', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 0) 
, ('9A66DF40-A725-45B7-BE92-562BC7BAA93F', 'Darter, Tallapoosa', 'Etheostoma tallapoosae', '00000000-0000-0000-0000-000000000000', 0) 
, ('AC8AB450-2F63-4AE6-81E1-564D1AE1A8E4', 'Shiner, Ribbon', 'Lythrurus fumeus', '00000000-0000-0000-0000-000000000000', 0) 
, ('8E751B9F-1FEE-4C47-B619-56D8DE17B35F', 'Darter, Emerald', 'Etheostoma baileyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('B603C82F-015A-4845-A4BC-56E77A936547', 'Shiner, Silverband', 'Notropis shumardi', '00000000-0000-0000-0000-000000000000', 0) 
, ('045D6B96-7A8D-423F-97A4-57B23D2AFEA9', 'Trout, Gila or Apache', 'Oncorhynchus gilae', '00000000-0000-0000-0000-000000000000', 0) 
, ('8620120A-89BB-4439-BBAE-587C0D08B5B6', 'Atlantic Tomcod', 'Microgadus tomcod', '00000000-0000-0000-0000-000000000000', 0) 
, ('9DDFBEA2-E397-4E41-B405-58909DC386AA', 'Sleeper, Fat', 'Dormitator maculatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FFF33B38-7782-47FF-AA1C-58A667F8CEC9', 'Sculpin, Malheur', 'Cottus bendirei', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('719A2112-FD1E-435F-BC03-59485EEBCC7C', 'Whitefish, Bonneville', 'Prosopium spilonotus', '00000000-0000-0000-0000-000000000000', 0) 
, ('76066C45-095E-4113-9636-595BE4DC30F9', 'Sculpin, Blue Ridge', 'Cottus caeruleomentum', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('14F3348B-A76D-4731-BD7D-5A056AFFD47A', 'Shiner, Bluehead', 'Pteronotropis hubbsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('A3A5ABA9-A010-4D1A-A999-5A09100D94A7', 'Alewife', 'Alosa pseudoharengus', '6951FE03-B0EA-443A-AF53-835CFEF43391', 0) 
, ('896837E4-3FE3-44C6-BAEE-5A490FBF64C8', 'Muskellunge', 'Esox masquinongy', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('77AFA313-6844-4ADF-91D9-5A7CA8F1D4D6', 'Darter, Harlequin', 'Etheostoma histrio', '00000000-0000-0000-0000-000000000000', 0) 
, ('67544F54-B27D-4F36-9865-5A9E53441D52', 'Sturgeon, White', 'Acipenser transmontanus', '7CBAFEAB-6B52-469B-AC47-F24F5F64C80E', 3) 
, ('86161D5B-B942-405A-BE76-5BAAA4088C30', 'Pupfish, Devil''s Hole', 'Cyprinodon diabolis', '00000000-0000-0000-0000-000000000000', 0) 
, ('6D31DFC9-C2E9-4464-8D27-5BB1F1DE7676', 'Shiner, Blueside', 'Lythrurus ardens', '00000000-0000-0000-0000-000000000000', 0) 
, ('0C426673-CFBF-4F66-B905-5BF4DC0A4338', 'Stoneroller, Bluefin', 'Campostoma pauciradii', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('B0553811-855A-4FDA-885C-5D5804AAEE70', 'Sucker, Bluehead', 'Catostomus discobolus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('54E3391A-2D86-40DD-BD76-5D783491EB7B', 'Sucker, Razorback', 'Xyrauchen texanus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('71C13285-8B04-47AC-8608-5DE8642785BB', 'Darter, Warrior', 'Etheostoma bellator', '00000000-0000-0000-0000-000000000000', 0) 
, ('67A07C9A-4D63-406E-A468-5E9345732154', 'Darter, Stippled', 'Etheostoma punctulatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('DAB26698-9AD6-4537-AED4-5F157DD54234', 'Sculpin, Spoonhead', 'Cottus ricei', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('60CFD5EF-B806-4739-963F-5F30A5613791', 'Dace, Northern Redbelly', 'Phoxinus eos', '00000000-0000-0000-0000-000000000000', 0) 
, ('ACD33836-23C8-44AE-ABF3-5F5CB7C31E1B', 'Dace, Pearl (Margarita)', 'Margariscus margarita', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('80A55D09-0C11-4C30-B4F8-5F5FC50177FE', 'Chub, Rosyface', 'Hybopsis rubrifrons', '00000000-0000-0000-0000-000000000000', 0) 
, ('1571DDC0-64B7-4F19-90C9-6003DEB60B0B', 'Shiner, Silverstripe', 'Notropis stilbius', '00000000-0000-0000-0000-000000000000', 0) 
, ('479F2F55-F05B-4E49-A0F4-6006CD4AAA3C', 'Buffalo, Bigmouth', 'Ictiobus cyprinellus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('836D5DD9-5B52-4146-A2C8-600CEE74C755', 'Giant oarfish', 'Regalecus glesne', 'ACAF8333-89BB-4F22-A406-645B4D41B33F', 0) 
, ('A4D2952C-41A7-40C3-9D7B-6057039BDB18', 'Darter, Olive', 'Percina squamata', '00000000-0000-0000-0000-000000000000', 0) 
, ('57B5C8E5-C533-4D3F-9355-60A76A299ED8', 'Sucker, Klamath Smallscale', 'Catostomus rimiculus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('E2D38B22-89BF-408C-A962-60D4BCF0FC19', 'Jumprock, Greater', 'Moxostoma lachneri', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('997B93CE-5DE2-41FF-A3F0-60FF0E4914DA', 'Darter, Cumberland', 'Etheostoma susanae', '00000000-0000-0000-0000-000000000000', 0) 
, ('D8F77469-3C8C-4FD9-9AF9-610BDFDE040B', 'Darter, Etowah', 'Etheostoma etowahae', '00000000-0000-0000-0000-000000000000', 0) 
, ('3B8588AD-942D-4B5F-9A38-61D974785522', 'Shiner, Red River', 'Notropis bairdi', '00000000-0000-0000-0000-000000000000', 0) 
, ('0F8FB06A-3E6B-4782-ACFC-621A7151DE56', 'Darter, Snail', 'Percina tanasi', '00000000-0000-0000-0000-000000000000', 0) 
, ('07FF3BD4-200F-44C8-9607-62BC29C1DF47', 'Darter, Speckled', 'Etheostoma stigmaeum', '00000000-0000-0000-0000-000000000000', 0) 
, ('7E905424-8DBB-4CDF-8D93-62D69BA33ACB', 'Sucker, Longnose', 'Catostomus catostomus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 2) 
, ('5AAF3C7B-FD94-4C76-9F60-63B423C3544A', 'Killifish, Spotfin', 'Fundulus luciae', '00000000-0000-0000-0000-000000000000', 0) 
, ('5BAFF162-EB0F-4B17-AA5E-642402201EEE', 'Madtom, Least', 'Noturus hildebrandi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D492B8DE-5F94-4478-A713-64534143EA94', 'Darter, Watercress', 'Etheostoma nuchale', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('CC583294-5008-4B4D-AF4B-64D2CA95FE12', 'Shiner, Rough', 'Notropis baileyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('DEA8B9FB-407B-42EB-81E1-657EB4D43C4B', 'Killifish, Waccamaw', 'Fundulus waccamensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('5F52072C-6528-4FD5-B775-65CA39CFF59D', 'Springfish, White River', 'Crenichthys baileyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('7F6928F8-ADE7-48D8-8099-6638A8CD4A39', 'Darter, Glassy', 'Etheostoma vitreum', '00000000-0000-0000-0000-000000000000', 0) 
, ('D05FE024-A6B8-48E3-8188-663E938488B9', 'Gar, Longnose', 'Lepisosteus osseus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('22F26140-8C5F-4C7C-B8F6-666D189D10C2', 'Paddlefish', 'Polyodon spathula', 'EBFBD2E6-B4B8-4617-8EFB-105FEAF68116', 1) 
, ('2F42B7DF-A074-42B7-AEE9-66857F65BED9', 'Chub, Shiner,', 'Notropis potteri', '00000000-0000-0000-0000-000000000000', 0) 
, ('9BB7993E-F157-4E9B-A714-66CB5BEEA78E', 'Sunfish, Everglades Pygmy', 'Elassoma evergladei', '00000000-0000-0000-0000-000000000000', 0) 
, ('E41D3ADC-818E-429D-95E2-66E9B44A89ED', 'Silverside, Brook', 'Labidesthes sicculus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('639804E8-BA06-4548-985F-66F98F78D491', 'Sucker, Klamath Largescale', 'Catostomus snyderi', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('C86807C6-7FFD-4971-9572-6721F1DED60B', 'Shiner, Comely', 'Notropis amoenus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FCF58413-543E-4AD4-9AE4-6728BB62BEFE', 'Trout, Aurora', 'Salvelinus fontinalis timagamiensis', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('947DF78B-5011-40C1-9420-67474D8AB673', 'Minnow, Sheepshead', 'Cyprinodon variegatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('24B1C9FE-CBFD-4CB2-A962-6777869E68FB', 'Dace, Blacknose Western', 'Rhinichthys atratulus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('0CE27555-C2E7-45FF-A384-67C81DF3B9F2', 'Darter, Sawcheek', 'Etheostoma serrifer', '00000000-0000-0000-0000-000000000000', 0) 
, ('55F4F191-09B3-401A-91C2-680A2055DD5D', 'Spotted Bullhead', 'Ameiurus serracanthus', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 0) 
, ('26A4C661-5452-4932-A65B-6856CAAFD7E8', 'Dace, Southern Redbelly', 'Phoxinus erythrogaster', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 32) 
, ('783DA1AF-0BF0-4D12-84A9-6862F0E90F74', 'Catfish, Hardhead', 'Ariopsis felis', '63E8C24B-CF58-482A-9FDF-B88A1D31BF9A', 0) 
, ('ACA46090-8766-4EBC-B59D-68D0095D38BF', 'Chub, Sonora', 'Gila ditaenia', '00000000-0000-0000-0000-000000000000', 0) 
, ('E75F6707-C5BE-49C1-AC60-6900197849D4', 'Shiner, Coastal', 'Notropis petersoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('C4E58F4A-B138-461E-92F3-697435BE9A43', 'Spinedace, Pahranagat', 'Lepidomeda altivelis', '00000000-0000-0000-0000-000000000000', 0) 
, ('2B574EBE-6D95-4545-810C-69886E1FBBFC', 'Trout, Lahontan cutthroat', 'Oncorhynchus clarki henshawi', '00000000-0000-0000-0000-000000000000', 0) 
, ('A9675019-0ECA-4763-BDA2-6991986A340F', 'Darter, Variegate', 'Etheostoma variatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('D7810A09-A636-4879-9D38-69B963641EFD', 'Madtom, Elegant', 'Noturus elegans', '00000000-0000-0000-0000-000000000000', 0) 
, ('E98F5815-8134-4510-82F8-6A39A540F3D9', 'Shiner, Fluvial', 'Notropis edwardraneyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('6A63FCE1-4DA9-421D-BB29-6ABE5C5BA755', 'Cavefish, Alabama', 'Speoplatyrhinus poulsoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('7E6CA021-D531-4AA6-B599-6AF1F71EC100', 'Chub, Lake', 'Couesius plumbeus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('4DD6B8B9-C174-47C6-93DE-6AF2738762CB', 'Minnow, Stargazing', 'Phenacobius uranops', '00000000-0000-0000-0000-000000000000', 0) 
, ('D8413CF5-273A-429A-AA21-6B033154F747', 'Darter, Wounded', 'Etheostoma vulneratum', '00000000-0000-0000-0000-000000000000', 0) 
, ('23A4985E-E045-4492-B8DC-6B56531772BA', 'Sucker, Spotted', 'Minytrema melanops', '00000000-0000-0000-0000-000000000000', 0) 
, ('30A4D7CF-ACCF-474E-A170-6B6D8FC8A4C3', 'Sculpin, Black', 'Cottus baileyi', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('3524109D-18F3-4EED-99F5-6BB9272FDBA9', 'Darter, Okaloosa', 'Etheostoma okaloosae', '00000000-0000-0000-0000-000000000000', 0) 
, ('8AD2C9DA-BEA7-42D0-8D5A-6C5BDBD6A824', 'Bass, Shoal', 'Micropterus cataractae', '00000000-0000-0000-0000-000000000000', 0) 
, ('DC38E981-2A0E-4F55-9179-6C6F9619CF0B', 'Chub, Creek', 'Semotilus atromaculatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('61474B4A-AFDF-4219-93ED-6C97CF97BD4F', 'Sleeper, Bigmouth', 'Gobiomorus dormitor', '00000000-0000-0000-0000-000000000000', 0) 
, ('FB77F10B-CA10-4FEC-A7EC-6CFEA3C827C5', 'Catfish, Blue', 'Ictalurus furcatus', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 4) 
, ('CC790CCE-6414-412C-B769-6D1AB571167D', 'Catish Tentacles', 'Ancistrus kellerae', '379EB483-4C8A-4D46-AFB4-5C9FC1BDED69', 0) 
, ('4A84AB5E-FC2E-4095-BF57-6D7BB2065A9F', 'Atlantic halibut', 'Hippoglossus hippoglossus', '5BCA0E49-A488-4FA9-9F3B-F23F34094E29', 0) 
, ('4E3FCB34-1E38-42C2-9B9D-6D8ADF92ED95', 'Darter, Greenbreast', 'Etheostoma jordani', '00000000-0000-0000-0000-000000000000', 0) 
, ('625EC91C-CC44-488C-8003-6DAA409B19A1', 'Topminnow, Blackspotted', 'Fundulus olivaceus', '00000000-0000-0000-0000-000000000000', 0) 
, ('14978D05-8348-40E4-9E5C-6DCEEBFD4E46', 'Minnow, Ozark', 'Notropis nubilus', '00000000-0000-0000-0000-000000000000', 0) 
, ('351656AA-474B-4EB3-A86F-6E1C6ADF9F8D', 'Darter, Goldline', 'Percina aurolineata', '00000000-0000-0000-0000-000000000000', 0) 
, ('88484F6F-08A1-4285-A47B-6E33F73B256B', 'Pirarucu', 'Arapaima gigas', '70DC9966-6353-4F46-9194-CE539A38C160', 0) 
, ('2234C31F-67A3-43E8-9D6A-6E54A5C31C00', 'Darter, Waccamaw', 'Etheostoma perlongum', '00000000-0000-0000-0000-000000000000', 0) 
, ('D893BDB0-3796-448D-AFCF-6E658EDE9802', 'Spinedace, Little Colorado', 'Lepidomeda vittata', '00000000-0000-0000-0000-000000000000', 0) 
, ('BAD0426A-37FE-48AC-8DEC-6E8EA17C06AE', 'Sunfish, Green', 'Lepomis cyanellus', '00000000-0000-0000-0000-000000000000', 0) 
, ('DE0BB250-4269-4AE3-BF81-6EC419848DF0', 'Darter, Trispot', 'Etheostoma trisella', '00000000-0000-0000-0000-000000000000', 4) 
, ('3B1B337C-8D09-4E78-98E8-6EDA17A752EB', 'Topminnow, Golden', 'Fundulus chrysotus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E423B40A-729F-4438-8227-6EE1C548C76E', 'Shiner, Golden', 'Notemigonus crysoleucas', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('B7643CA4-59AD-4FD5-A9C1-6F6545A72A40', 'Chub, Alvord', 'Gila alvordensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('C8E9BA68-99A1-48DB-95F9-6FFE3F823866', 'Shiner, Topeka', 'Notropis topeka', '00000000-0000-0000-0000-000000000000', 0) 
, ('E71516CD-D635-4FB9-8D42-70B852791DFF', 'Killifish, Rainwater', 'Lucania parva', '00000000-0000-0000-0000-000000000000', 0) 
, ('857DC3BC-E143-4970-9472-7139401416C3', 'Quillback', 'Carpiodes cyprinus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('4DAD6C0D-41EE-4971-8619-716EEFDC6C6A', 'Madtom, Mountain', 'Noturus eleutherus', '00000000-0000-0000-0000-000000000000', 0) 
, ('AA688A1A-198F-438F-83D9-724588022FF5', 'Chub, Least', 'Iotichthys phlegethontis', '00000000-0000-0000-0000-000000000000', 0) 
, ('94A3BF91-93E2-4DD8-9EF2-72832DD17529', 'Darter, Leopard', 'Percina pantherina', '00000000-0000-0000-0000-000000000000', 0) 
, ('C04CAB9B-88B1-40F3-AD9E-72C6CCC27495', 'Darter, Maryland', 'Etheostoma sellare', '00000000-0000-0000-0000-000000000000', 0) 
, ('C02D86EE-53D9-40B2-BE80-73257DDCCF16', 'Shiner, Beautiful', 'Cyprinella formosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('8FE42AB2-52B6-428F-9ED0-73CE3381B4C4', 'Sucker, Sonora', 'Catostomus in signis', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('5AB8A0EE-A5CA-43E6-B628-73E2BC12266E', 'Crappie, Black', 'Pomoxis nigromaculatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('1782F673-3034-4585-81AB-73EA30F78527', 'Darter, Tessellated', 'Etheostoma olmstedi', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('C358EF9C-4C87-4EF5-887B-740139CD3772', 'Gar, Alligator', 'Atractosteus spatula', '65602359-3AC9-4304-9A46-2DC7619DF12C', 3) 
, ('490531EB-C93D-4A50-8E08-74612B6ECE39', 'Darter, Orangebelly', 'Etheostoma radiosum', '00000000-0000-0000-0000-000000000000', 0) 
, ('86EFC393-062A-4538-BB82-7470EE4B386F', 'Chub, Prairie', 'Macrhybopsis australis', '00000000-0000-0000-0000-000000000000', 0) 
, ('269241BB-9051-47F9-AF70-74E4190109E0', 'Darter, Sooty', 'Etheostoma olivaceum', '00000000-0000-0000-0000-000000000000', 0) 
, ('945E4C3F-73E5-4D82-BAFD-752AE06BF074', 'Darter, Bloodfin', 'Etheostoma sanguifluum', '00000000-0000-0000-0000-000000000000', 0) 
, ('819ED521-D713-4AE6-9A58-75B36CA32D55', 'Lahontan Redside', 'Richardsonius egregius', '00000000-0000-0000-0000-000000000000', 0) 
, ('DBA55C88-B6F6-4A74-983E-75D95E63A3D8', 'Shiner, Bannerfin', 'Cyprinella leedsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('7C98B042-A11C-441D-BD1F-77067B2C7EB3', 'Shiner, Telescope', 'Notropis telescopus', '00000000-0000-0000-0000-000000000000', 0) 
, ('295FF564-5461-49FA-8051-77303500F7BF', 'Silverside, Mississippi', 'Menidia audens', '00000000-0000-0000-0000-000000000000', 0) 
, ('A604C025-3573-433F-AE27-78C20AF348D9', 'Darter, Barrens', 'Etheostoma forbesi', '00000000-0000-0000-0000-000000000000', 0) 
, ('79A8423E-2A09-49EC-B843-78F5A1DE13B8', 'Chub, Speckled', 'Macrhybopsis aestivalis', '00000000-0000-0000-0000-000000000000', 0) 
, ('2A64AC33-222B-4248-BF0E-79B0A5EAF105', 'Bass, Redeye', 'Micropterus coosae', '00000000-0000-0000-0000-000000000000', 0) 
, ('E8987980-2C30-4AC2-AB18-79D39C421A24', 'Logperch, Ozark', 'Percina fulvitaenia', '00000000-0000-0000-0000-000000000000', 0) 
, ('CDE5395F-A377-487E-96F5-79EA5ADFAD10', 'Shiner, Cherryfin', 'Lythrurus roseipinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('37437E9E-7D38-41E8-AC7F-7A4CB5F6B318', 'Darter, Saffron', 'Etheostoma flavum', '00000000-0000-0000-0000-000000000000', 0) 
, ('F6280E4F-8AC4-45DB-9B4D-7A593FC59E2B', 'Gar, Shortnose', 'Lepisosteus platostomus', '65602359-3AC9-4304-9A46-2DC7619DF12C', 0) 
, ('F83D9508-BF50-41B8-B22C-7ACCBB6713DD', 'African pompano', 'Alectis ciliaris', '03FE2000-10FC-4F9F-BFB3-7712A98B8CF9', 0) 
, ('0544C73B-2EE5-455F-9D47-7AFD429E9E6C', 'Darter, Slenderhead', 'Percina phoxocephala', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('855B3EAB-2590-4B90-B61D-7B4B52F455CF', 'Saugeye', 'Stizostedion vitreum x Stizostedion canadense', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 1) 
, ('F16C1608-B1C8-46D8-B51D-7B4EB5221796', 'Gambusia, Largespring', 'Gambusia geiseri', '00000000-0000-0000-0000-000000000000', 0) 
, ('C99308F4-2BBE-4B06-B2F2-7B751346654C', 'Sculpin, Ozark', 'Cottus hypselurus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('785AD4BC-01A1-4CAA-ADD6-7B9A399CFAE3', 'Madtom, Black', 'Noturus funebris', '00000000-0000-0000-0000-000000000000', 0) 
, ('14C17863-0473-4D7D-92B6-7CBB964E7BB7', 'Sculpin, Pacific Staghorn', 'Leptocottus armatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('1862045E-59C7-4473-B07F-7CCAEEEBD41F', 'Sunfish, Longear', 'Lepomis megalotis', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 32) 
, ('F4E3202E-7B48-4256-8A55-7DE3E1F7363A', 'Topminnow, Gila', 'Poeciliopsis occidentalis', '00000000-0000-0000-0000-000000000000', 0) 
, ('529CAC2B-DB9F-4D96-A96B-7DF31F5E4A87', 'Atlantic Bonito', 'Sarda sarda', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 3) 
, ('75F85004-FB74-48CC-B6DA-7E5017E58509', 'Bullhead, Brown', 'Ameiurus nebulosus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('19F45132-B1BC-4F3C-9896-7EF45143DBC1', 'Sucker, Sacramento', 'Catostomus occidentalis', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('30842DDE-EDFB-49EE-A803-7F8F73360D2B', 'Shiner, Silverside', 'Notropis candidus', '00000000-0000-0000-0000-000000000000', 0) 
, ('93801BEB-0954-42C5-B8EB-80CEC9DAE62E', 'Lamprey, Western Brook', 'Lampetra richardsoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('761E293A-384D-4FB7-A37B-8102DF6E3B25', 'Shiner, Ozark', 'Notropis ozarcanus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FFA25137-B013-4D25-B50A-815CEB4F0735', 'Darter, Orangefin', 'Etheostoma bellum', '00000000-0000-0000-0000-000000000000', 0) 
, ('72AC2B77-29A7-48E4-83A4-8178313BA4FB', 'Shiner, Phantom', 'Notropis orca', '00000000-0000-0000-0000-000000000000', 0) 
, ('C34813AB-16F6-417A-ABB4-8181D1929027', 'Darter, Blackbanded', 'Percina nigrofasciata', '00000000-0000-0000-0000-000000000000', 0) 
, ('16DDA0B7-CF20-4E74-B227-81CEF89C1E64', 'Chub, River', 'Nocomis micropogon', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('704947AA-441C-4270-9811-8275D94B76D5', 'Sucker, Largescale', 'Catostomus macrocheilus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('5B5BD392-8BAD-4B8D-9E43-82D3D60F8D1F', 'Shiner, Tricolor', 'Cyprinella trichroistia', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('A9286A7C-CE5C-497A-B7E0-82DF01170718', 'Atlantic mackerel', 'Scomber scombrus', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 0) 
, ('E2A2D7C2-6B08-43D3-90F2-83911F25A422', 'Shiner, Cahaba', 'Notropis cahabae', '00000000-0000-0000-0000-000000000000', 0) 
, ('98C3A9A5-57A5-47F6-9EF9-83A763DB21AE', 'Studfish, Northern', 'Fundulus catenatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('C23D662E-82B8-411C-9BF2-83AAFFF7696F', 'Sucker, Blackfin', 'Thoburnia atripinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('F4655DC6-4B0B-4FDA-B08A-83E668785713', 'Atlantic bluefin tuna', 'Thunnus thynnus', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 0) 
, ('B17B6277-E71D-450A-B0DE-8452E78BBF57', 'Killifish, Banded', 'Fundulus diaphanus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('4FECF17E-A86E-40C0-933E-84FA6FD79AA6', 'Shiner, Taillight', 'Notropis maculatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('038B5ECF-02D1-4E8F-A01D-85668C2FEA12', 'Shiner, Weed', 'Notropis texanus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('566E723D-6A0E-4958-8684-85CF2EDC2AE0', 'Topminnow, Starhead', 'Fundulus dispar', '66F6E067-D437-410A-BE0E-AF428C86A6FA', 0) 
, ('52A4329E-082B-4DF5-B368-85E218A13A68', 'Silverside, Inland', 'Menidia beryllina', '00000000-0000-0000-0000-000000000000', 0) 
, ('F124F917-D11F-4ED9-9B59-863D184CBFED', 'Trout, Brook', 'Salvelinus fontinalis', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('6A5428CD-1035-41AC-8757-8648B70C4641', 'Darter, Western Sand', 'Ammocrypta clara', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('9A7BE499-8726-4EAE-84C1-864F0E0EED27', 'Hardhead', 'Mylopharodon conocephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('9CA6F55E-256E-449E-81C5-8800AEFF0C39', 'Shiner, Fieryblack', 'Cyprinella pyrrhomelas', '00000000-0000-0000-0000-000000000000', 0) 
, ('A32AB601-AC5C-4757-BF0A-8831304D67CA', 'Sculpin, Shoshone', 'Cottus greenei', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('E165A025-141D-4E1A-B018-88D4864FD253', 'Cavefish, Northern', 'Amblyopsis spelaea', 'B3B6FD5A-DB37-4AFA-B94D-EFC7C93C6A5C', 0) 
, ('EDF287D7-DC0F-40C1-82E5-891DBF5C7305', 'Dace, Rosyside', 'Clinostomus funduloides', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('FDB50F90-D01B-4928-AF51-897180D98572', 'Darter, Brook', 'Etheostoma burri', '00000000-0000-0000-0000-000000000000', 0) 
, ('2AF2731A-67C6-4107-911C-898E6B23A174', 'Arctic Grayling', 'Thymallus arcticus', '00000000-0000-0000-0000-000000000000', 0) 
, ('C51350F4-FE17-45EC-955F-89B9309710B0', 'Chub, Bigeye', 'Hybopsis amblops', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('7AF813C6-7D19-4C99-8B2E-89DE490F60FD', 'Redfin Pickerel', 'Esox americanus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FD50A6B8-68DF-4208-89CF-89F66AE0C669', 'Dace, Relict', 'Relictus solitarius', '00000000-0000-0000-0000-000000000000', 0) 
, ('CC76E477-AC98-49CB-BE1A-8A0D439134A3', 'Chub, Tui', 'Gila bicolor', '00000000-0000-0000-0000-000000000000', 0) 
, ('5D069A33-6B36-4314-BD49-8A32A6C92245', 'Salmon, Chinook', 'Oncorhynchus tshawytscha', '00000000-0000-0000-0000-000000000000', 1) 
, ('AF73CAE1-F7B4-4137-9BE5-8A36C1F97AF1', 'Shiner, Rainbow', 'Notropis chrosomus', '00000000-0000-0000-0000-000000000000', 0) 
, ('89DB7905-DF03-4636-BBD0-8A71060E4D2F', 'Cavefish, Southern', 'Typhlichthys subterraneus', '00000000-0000-0000-0000-000000000000', 0) 
, ('81378354-537A-42BF-9AB3-8A87C7A7641B', 'Madtom, Slender', 'Noturus exilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('FC7B02AC-8535-4B7E-85F4-8A9F59E260FB', 'Woundfin', 'Plagopterus argentissimus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A26237A1-4DD6-4168-88E4-8B5254AC2D74', 'Logperch, Bigscale', 'Percina macrolepida', '00000000-0000-0000-0000-000000000000', 0) 
, ('2850107E-9E7C-4AC4-8953-8B6189255961', 'Shiner, Crescent', 'Luxilus cerasinus', '00000000-0000-0000-0000-000000000000', 0) 
, ('874AA9B3-B8B0-40FA-8320-8BC595A734BB', 'Sucker, Yaqui', 'Catostomus bernardini', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('0EA7F6F6-2209-437D-9503-8BDF3B0B6C8B', 'Bass, White', 'Morone chrysops', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('305852F6-863A-47C2-9CEF-8C001C2139B5', 'Sculpin, Wood River', 'Cottus leiopomus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('A2DF56D0-B0A6-4967-B0B6-8C281BCFA44C', 'Darter, Tuskaloosa', 'Etheostoma douglasi', '00000000-0000-0000-0000-000000000000', 0) 
, ('7BFBFDD6-3F8E-4AC1-AD5C-8C36B7918D77', 'Shiner, Cardinal', 'Luxilus cardinalis', '00000000-0000-0000-0000-000000000000', 0) 
, ('2405A055-FF3C-475C-9399-8CEB709B5419', 'Shiner, Spottail', 'Notropis hudsonius', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('8DA9EDBE-BC1A-499F-A417-8D08B0D4040D', 'Chub, Blotched', 'Erimystax insignis', '00000000-0000-0000-0000-000000000000', 0) 
, ('C71E0DA0-559E-45F1-A917-8D6A263B70BF', 'Smelt, Delta', 'Hypomesus transpacificus', '00000000-0000-0000-0000-000000000000', 0) 
, ('61F1B317-5148-43AE-8AF4-8D9CDF4B5616', 'Stickleback, Brook', 'Culaea inconstans', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('E11ACC00-DF24-4EF5-AF16-8DCE73FF888D', 'Sunfish, Northern', 'Lepomis peltastes', '00000000-0000-0000-0000-000000000000', 0) 
, ('A850AA33-E6CA-4B14-846A-8E2BC50B968D', 'Mudminnow, Olympic', 'Novumbra hubbsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('4A35090F-DD25-4D1B-A81F-8E57CF7B98B3', 'Logperch, Roanoke', 'Percina rex', '00000000-0000-0000-0000-000000000000', 0) 
, ('54DDA357-3BBE-4F24-84B9-8E697E9635B6', 'Darter, Highland Rim', 'Etheostoma kantuckeense', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('ED088D1F-8F67-4638-A917-8E9878DE3858', 'Darter, Egg-mimic', 'Etheostoma pseudovulatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('03482E38-439A-4DA3-B9A7-8F03C1B04C9F', 'Redhorse, River', 'Moxostoma carinatum', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('B87B31AF-1ED6-4FA0-A9F9-8F793F856AD9', 'Carp, Black', 'Mylopharyngodon piceus', '00000000-0000-0000-0000-000000000000', 1) 
, ('E5827A94-C741-4F65-9F6D-8F7B0956DCAA', 'Shiner, Channel', 'Notropis wickliffi', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('C22F63FB-692F-42FC-8481-8F868CFA3377', 'Smelt, Longfin', 'Spirinchus thaleichthys', '00000000-0000-0000-0000-000000000000', 0) 
, ('4C87E7B4-B637-44A6-A0F1-90C9FE4ABC84', 'Shiner, Pallid', 'Hybopsis amnis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('62463DE6-7913-425A-85C7-9148D4BCC75A', 'Perch, White', 'Morone americana', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('D2285EB2-8B8A-4FA6-ACBF-914F1DE0B3E3', 'Gambusia, Amistad', 'Gambusia amistadensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('FAE9C13C-8D80-46D9-885D-9180BDEB77F0', 'Darter, Kentucky', 'Etheostoma rafinesquei', '00000000-0000-0000-0000-000000000000', 0) 
, ('5CB4CCA5-B429-4336-89D6-91BB27B9EA19', 'Sleeper, Akupa', 'Eleotris sandwicensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('798647A3-D937-4667-A843-91E4C56FF479', 'Sucker, Torrent', 'Thoburnia rhothoeca', '00000000-0000-0000-0000-000000000000', 0) 
, ('F0FBE9D6-0592-417D-8799-9216361CB91B', 'Darter, Redband', 'Etheostoma luteovinctum', '00000000-0000-0000-0000-000000000000', 0) 
, ('9CD6241E-67ED-45AD-981D-929CC5E1E87B', 'Sucker, Harelip', 'Moxostoma lacerum', '00000000-0000-0000-0000-000000000000', 0) 
, ('0898A5A3-40D7-4DF4-AF08-92B3327C1B35', 'Carpsucker, River', 'Carpiodes carpio', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('A8D140DA-B722-4D13-90D3-92F1B0783B6C', 'Chub, Sturgeon', 'Macrhybopsis gelida', '00000000-0000-0000-0000-000000000000', 0) 
, ('F65F13DB-893B-47EB-AC9A-93085D41CE4E', 'Sculpin, Margined', 'Cottus marginatus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('A58134AD-1CC4-4B25-B957-9324138451BC', 'Darter, Barcheek', 'Etheostoma obeyense', '00000000-0000-0000-0000-000000000000', 0) 
, ('8B830B92-F585-4C28-B450-933B55102CE4', 'Lamprey, Kern Brook', 'Lampetra hubbsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('FB7715DB-5F1A-4714-AD93-935626A125FA', 'Topminnow, Blackstripe', 'Fundulus notatus', '00000000-0000-0000-0000-000000000000', 4) 
, ('191608F2-692D-46FA-A98E-939FB7A9EDFE', 'Killifish, Gulf', 'Fundulus grandis', '00000000-0000-0000-0000-000000000000', 0) 
, ('987A5662-103D-4947-BBF7-93A1EED18AE7', 'Trout, Dolly Varden', 'Salvelinus malma', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('49D46080-E1E9-468F-81A6-94378BF14C48', 'Madtom, Frecklebelly', 'Noturus munitus', '00000000-0000-0000-0000-000000000000', 0) 
, ('93BE68B9-1999-4AD8-88A8-94A5D9DD68D5', 'Sand Roller', 'Percopsis transmontana', '00000000-0000-0000-0000-000000000000', 0) 
, ('C8E8AECA-04AE-46F1-806C-9503A3861932', 'Chubsucker, Creek', 'Erimyzon oblongus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('62806298-151A-4BF4-8D89-951A46749B80', 'Darter, Blackside', 'Percina maculata', '00000000-0000-0000-0000-000000000000', 4) 
, ('0B6BB884-797F-4A0C-89BE-9530F5452284', 'Sucker, Alabama Hog', 'Hypentelium etowanum', '00000000-0000-0000-0000-000000000000', 0) 
, ('DDC5A2B7-A4F7-4EB7-97CD-96074F52359E', 'Whitefish, Round', 'Prosopium cylindraceum', '00000000-0000-0000-0000-000000000000', 1) 
, ('23CB17FE-6717-43C0-A8DA-963E06CA106A', 'Pupfish, Conchos', 'Cyprinodon eximius', '00000000-0000-0000-0000-000000000000', 0) 
, ('5E71F900-F18E-45A0-951B-9651B697ADAD', 'Sculpin, Slender', 'Cottus tenuis', '00000000-0000-0000-0000-000000000000', 0) 
, ('F3C65C73-F913-43B8-9F22-965AB095D13E', 'Trout, Lake', 'Salvelinus namaycush', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('6E5DD45F-B076-4F10-B3F5-96752C501CD6', 'Minnow, Nueces Roundnose', 'Dionda serena', '00000000-0000-0000-0000-000000000000', 0) 
, ('892057BE-36C0-423B-A260-969A3D64E8CF', 'Stoneroller, Central', 'Campostoma anomalum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 32) 
, ('F9C287DA-E2EF-49FE-ADF4-96C886BB7AB1', 'Sculpin, Bear Lake', 'Cottus extensus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('20E2A96F-F2D2-47AA-A637-96F07A004197', 'Shiner, Redlip', 'Notropis chiliticus', '00000000-0000-0000-0000-000000000000', 0) 
, ('DC255219-219E-431F-9B4D-9791B87AA92D', 'Dace, Speckled', 'Rhinichthys osculus', '00000000-0000-0000-0000-000000000000', 0) 
, ('9CE4ECC4-5235-49AF-A7F8-9810C558CE67', 'Shiner, Mimic', 'Notropis volucellus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('740E988E-326A-40AC-A917-983110A1E602', 'O''Opu Alamo''o', 'Lentipes concolor', '00000000-0000-0000-0000-000000000000', 0) 
, ('9C2680F7-9347-41D8-85DC-9878B0036F59', 'Cuckoo Catfish', 'Synodontis multipunctatus', '2255FFCE-4214-4629-9E87-73B3F0F30171', 8) 
, ('E7CE8149-68DE-41D7-AF6D-98F28B118620', 'Darter, Spottail', 'Etheostoma squamiceps', '00000000-0000-0000-0000-000000000000', 0) 
, ('D4FD469F-89BB-471C-BB03-9940FDA85FC2', 'Topminnow, Broadstripe', 'Fundulus euryzonus', '00000000-0000-0000-0000-000000000000', 0) 
, ('2A1D7D84-6918-4C07-BDD0-9A494BBB4C29', 'Minnow, Guadalupe Roundnose', 'Dionda nigrotaeniata', '00000000-0000-0000-0000-000000000000', 0) 
, ('218FB011-14D7-48E9-9802-9A99B3AE2B22', 'Shiner, Whitemouth', 'Notropis alborus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('DDF8A985-437C-4864-A7B1-9AD9BEDF9437', 'Madtom, Pygmy', 'Noturus stanauli', '00000000-0000-0000-0000-000000000000', 0) 
, ('DD3F73DE-F324-47FC-A8D7-9B029326AAC5', 'Darter, Greenthroat', 'Etheostoma lepidum', '00000000-0000-0000-0000-000000000000', 0) 
, ('5643E003-D69A-4765-8FEA-9B12C46631E9', 'Stickleback, Ninespine', 'Pungitius pungitius', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('2C682A43-8C59-4B8D-8502-9B1420A134D0', 'Sharpfin Chubsucker', 'Erimyzon tenuis', '00000000-0000-0000-0000-000000000000', 0) 
, ('2A46AC7B-F31F-4244-9113-9B4A321EC7C7', 'Sunfish, Dollar', 'Lepomis marginatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('8463882E-FB3F-4CDC-A295-9B4D53595675', 'Sculpin, Marbled', 'Cottus klamathensis', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('E7CECFF0-3CB8-4343-A56B-9B9BB0CC26C9', 'Cisco, Longjaw', 'Coregonus alpenae', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 0) 
, ('5F96F577-0BFE-4A98-BE8B-9BB7991C8D2E', 'Prussian carp', 'Carassius gibelio', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('09B1C937-10C1-4E35-BAB8-9C6C0F6C87CA', 'Darter, Choctawhatchee', 'Etheostoma davisoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('02E92958-CD55-420E-8CD3-9D49F2F62886', 'Logperch', 'Percina caprodes', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('1C641E2F-C5C0-4AA6-8F3E-9D4EA9AF46E8', 'Gambusia, Blotched', 'Gambusia senilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('29C41444-AFF6-4A8A-A369-9D7AC56B6540', 'Pupfish, Leon Springs', 'Cyprinodon bovinus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E59E7735-9F8D-4E3F-B43A-9D929C64D065', 'Pacific halibut', 'Hippoglossus stenolepis', '5BCA0E49-A488-4FA9-9F3B-F23F34094E29', 3) 
, ('9C2363E8-6DEF-43F5-89DA-9DE0D5E3083C', 'Perch, Sacramento', 'Archoplites interruptus', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('0EBB807D-5361-48FE-BA79-9DED09E32261', 'Chub, Virgin River', 'Gila seminuda', '00000000-0000-0000-0000-000000000000', 0) 
, ('DCDB4B8A-7802-46F4-9B3E-9E0911D6C104', 'Darter, Bluespar', 'Etheostoma meadiae', '00000000-0000-0000-0000-000000000000', 0) 
, ('7CADF2D1-0BC0-4076-A355-9E3691D41C05', 'Pickerel, Grass', 'Esox americanus vermiculatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('9DFFFFC9-CA34-47A3-A2D9-9EE28805802A', 'Goby, Tubenose', 'Proterorhinus marmoratus', 'F49FAEF0-1444-42A8-B8B0-D315172686AE', 4) 
, ('AC4A50EB-B763-4F1F-85BA-9F152DC61401', 'Chub, Northern Leatherside', 'Lepidomeda copei', '00000000-0000-0000-0000-000000000000', 0) 
, ('08D7FF68-80DB-44F3-98ED-9F21B0D41009', 'Darter, Holiday', 'Etheostoma brevirostrum', '00000000-0000-0000-0000-000000000000', 0) 
, ('0476ED42-011A-44F9-81C5-9F5E6BCEE1EF', 'Sucker, Blue', 'Cycleptus elongatus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('FA9CD3C1-F1ED-4FBD-A9EC-A00BE4D6FB39', 'Darter, Greenside', 'Etheostoma blennioides', '00000000-0000-0000-0000-000000000000', 0) 
, ('FB7D6818-9E21-425F-B878-A023886B2016', 'Shiner, Redfin', 'Lythrurus umbratilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('4F20B429-6094-4061-888C-A03FB537121E', 'Goldfish', 'Carassius auratus', '00000000-0000-0000-0000-000000000000', 0) 
, ('4CE6731D-974B-4751-AD97-A05390816934', 'Darter, Guardian', 'Etheostoma oophylax', '00000000-0000-0000-0000-000000000000', 0) 
, ('DC4583A9-A05A-4861-B5B3-A068215641FB', 'Minnow, Loach', 'Rhinichthys cobitis', '00000000-0000-0000-0000-000000000000', 0) 
, ('B935F5AB-984C-49E2-88A1-A104356DBDAF', 'Sunfish, Blackbanded', 'Enneacanthus chaetodon', '00000000-0000-0000-0000-000000000000', 0) 
, ('8326C862-E80F-40A4-9AA1-A14D4A175A8E', 'Darter, Southern Sand', 'Ammocrypta meridiana', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('0DCD4252-C8DA-4322-AF8E-A171DAFFD7F2', 'Lamprey, Mountain Brook', 'Ichthyomyzon greeleyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D822B7D0-72D5-40BC-B8A3-A1AEBE06EF7B', 'Darter, Arkansas', 'Etheostoma cragini', '00000000-0000-0000-0000-000000000000', 0) 
, ('969C00E3-1ED1-4845-BFFC-A1DC51E2105D', 'Catfish, Channel', 'Ictalurus punctatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('2E51DDCE-F9BD-4459-9471-A1E84A9463FC', 'Darter, Tuckasegee', 'Etheostoma gutselli', '00000000-0000-0000-0000-000000000000', 0) 
, ('33D226F2-D730-446E-89DB-A286C04E5C71', 'Shiner, Warpaint', 'Luxilus coccogenis', '00000000-0000-0000-0000-000000000000', 0) 
, ('1477E844-FAFF-4297-B801-A2A8363B4F80', 'Sturgeon, Shovelnose', 'Scaphirhynchus platorynchus', '7CBAFEAB-6B52-469B-AC47-F24F5F64C80E', 1) 
, ('612CDABE-3E7D-4D53-8DED-A36A63138F80', 'Bass, Roanoke', 'Ambloplites cavifrons', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('B0FE3AF1-2652-4AD0-9786-A420634E0ECB', 'Flier', 'Centrarchus macropterus', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('61832FE9-2F76-4F7F-9732-A447C4303873', 'Albacore Tuna', 'Thunnus alalunga', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 1) 
, ('7F810CC3-5580-4492-A0AC-A4F1B8AE5BE5', 'Sunfish, Redbreast', 'Lepomis auritus', '00000000-0000-0000-0000-000000000000', 0) 
, ('FE084857-90BC-41DE-BA90-A54F1C7D7A40', 'Sculpin, Fourhorn', 'Myoxocephalus quadricornis', '00000000-0000-0000-0000-000000000000', 0) 
, ('32975F54-4568-40EC-B2AE-A5DBC4088927', 'Sucker, White', 'Catostomus commersoni', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 2) 
, ('95EA363C-3462-4917-96FB-A5E624079F0E', 'Dace, Blackside', 'Phoxinus cumberlandensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('092CED6F-B76D-432E-81E9-A6408156A4A4', 'Goby, Slashcheek', 'Ctenogobius pseudofasciatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('238ED612-C010-44E0-A8BC-A660AD105A82', 'Trout, Cutthroat', 'Oncorhynchus clarki', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('5CEB8859-EB4F-497D-BD50-A7154290E1E3', 'Chub, Streamline', 'Erimystax dissimilis', '00000000-0000-0000-0000-000000000000', 0) 
, ('BA547C74-45E0-490E-9AAA-A77F1466B208', 'Shiner, Broadstripe', 'Pteronotropis euryzonus', '00000000-0000-0000-0000-000000000000', 0) 
, ('F2324C47-D817-4405-A800-A7D965DECF8A', 'Darter, Boulder', 'Etheostoma wapiti', '00000000-0000-0000-0000-000000000000', 0) 
, ('4067B944-4ABE-4AED-975B-A7E3FE14BAD2', 'Minnow, Cypress', 'Hybognathus hayi', '00000000-0000-0000-0000-000000000000', 0) 
, ('DC5FB219-E44C-42FF-8636-A8646F9B2911', 'Darter, Lipstick', 'Etheostoma chuckwachatte', '00000000-0000-0000-0000-000000000000', 0) 
, ('5482A86D-7962-4F66-BA0B-A8DDA45E1DB8', 'Sucker, Santa Ana', 'Catostomus santaanae', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('C745DEC1-8F07-41E0-91AE-A8DDA6AE7957', 'Shiner, Blackmouth', 'Notropis melanostomus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B8C72B8A-D4CC-43EC-806E-A9F8300FDF51', 'Chub, Thicklip', 'Cyprinella labrosa', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('0FE64435-5558-410C-B9D2-AA255079860E', 'Shiner, Arkansas River', 'Notropis girardi', '00000000-0000-0000-0000-000000000000', 0) 
, ('7B820B8B-8DD0-47DC-B2DB-AA31F5171A5C', 'Jumprock, Bigeye', 'Moxostoma ariommum', '00000000-0000-0000-0000-000000000000', 0) 
, ('298C6A25-D43D-4A02-B963-AACB26631279', 'Darter, Striped', 'Etheostoma virgatum', '00000000-0000-0000-0000-000000000000', 0) 
, ('1E182825-076F-4123-97CF-AAF964372715', 'Drum, Freshwater', 'Aplodinotus grunniens', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('BE0A82E6-1316-4D34-B1CF-AB3644EF5515', 'Madtom, Ouachita', 'Noturus lachneri', '00000000-0000-0000-0000-000000000000', 0) 
, ('30B8D25A-17A6-4977-97F4-AB3E3BF43F67', 'Striped Mullet', 'Mugil cephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('9859D09F-26DA-4B01-B8CC-AB534153FB2F', 'Darter, Shield', 'Percina peltata', '00000000-0000-0000-0000-000000000000', 0) 
, ('349A9340-ACCA-493B-B091-AB560F64A525', 'Molly, Sailfin', 'Poecilia latipinna', '00000000-0000-0000-0000-000000000000', 0) 
, ('F61E810E-8F99-4D78-BC31-AB6B0BB27C0A', 'Dace, Leopard', 'Rhinichthys falcatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('662A9E6A-B914-489C-A9B3-AB79AFB0E164', 'Sculpin, Pygmy', 'Cottus paulus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('9B5E8006-303B-474C-BD5C-AB9877A048AA', 'Shad, Gizzard', 'Dorosoma cepedianum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('101CD939-66F0-4817-91F2-AB9A631BEEA3', 'Eel, American', 'Anguilla rostrata', 'A828124A-8C6C-4B27-851D-CF2EB879FFF2', 2) 
, ('D0AA7EEB-0512-4D67-93A2-AC19FF6186EB', 'Darter, Alabama', 'Etheostoma ramseyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('15258B60-5875-4058-A2EC-AC394B76FB1D', 'Sculpin, Pit', 'Cottus pitensis', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('4C414E34-187D-49B7-B104-AD8FBE51B4AD', 'Logperch, Conasauga', 'Percina jenkinsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('00ED444B-2917-4B00-A53E-ADC53E74A191', 'Shiner, Bigeye', 'Notropis boops', '00000000-0000-0000-0000-000000000000', 0) 
, ('A410C9EF-CCB1-4E4B-A561-AE6A97A4379F', 'Pupfish, Pecos', 'Cyprinodon pecosensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('5BC0ABA2-033B-4868-B741-AE9DE8A068DE', 'Jumprock, Blacktip', 'Moxostoma cervinum', '00000000-0000-0000-0000-000000000000', 0) 
, ('DEBDE02D-AB7E-4B59-829B-AEF0841BEAE3', 'Pike, Blue', 'Sander vitreus', '00000000-0000-0000-0000-000000000000', 1) 
, ('929388FC-B7C8-45E8-89D4-AF37EF3F3C8E', 'Darter, Bayou', 'Etheostoma rubrum', '00000000-0000-0000-0000-000000000000', 0) 
, ('26C05A89-6D81-4275-810E-AF5138A4E21B', 'Chub, Redtail', 'Nocomis effusus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A6B68DDF-CB8C-4E62-9DED-AF641D80D3CC', 'Sucker, Roanoke Hog', 'Hypentelium roanokense', '00000000-0000-0000-0000-000000000000', 0) 
, ('ABA1EB5C-2B29-45DD-A326-AFAF69DDF3B9', 'Darter, Kanawha', 'Etheostoma kanawhae', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('102AC336-D6E3-412E-BACE-AFC655B9593F', 'Shiner, Tamaulipas', 'Notropis braytoni', '00000000-0000-0000-0000-000000000000', 0) 
, ('8997AB7F-195E-4F23-B665-B06A93F40D33', 'Darter, Johnny', 'Etheostoma nigrum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('BD1B1382-01EA-4424-B2C4-B06BA3BAF470', 'Shiner, Popeye', 'Notropis ariommus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D0F2A433-5655-4BBE-A8F1-B0A12FB64EF1', 'Sucker, Rio Grande', 'Catostomus plebeius', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('47E39384-D359-48BA-8BAF-B15C679482E4', 'Goldeye', 'Hiodon alosoides', '00000000-0000-0000-0000-000000000000', 0) 
, ('B6F25EB8-20AA-4401-BDFC-B21C74F5E5A1', 'Chub, Bull', 'Nocomis raneyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('438B6EAE-A513-4CE0-A6CE-B21D2680C8A9', 'Darter, Headwater', 'Etheostoma lawrencei', '00000000-0000-0000-0000-000000000000', 0) 
, ('D83AE6E1-51EF-444E-A2D6-B24D95786AD9', 'Sucker, Snake River', 'Chasmistes muriei', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('6DBF1306-DC10-421A-A29B-B260D540A0AE', 'Trout, Brown', 'Salmo trutta', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('8D571880-5049-4D8A-8C76-B297A0B67FE0', 'Shiner, Bandfin', 'Luxilus zonistius', '00000000-0000-0000-0000-000000000000', 0) 
, ('E0B14122-A4FD-4577-BEAB-B3FADC827E45', 'Darter, Amber', 'Percina antesella', '00000000-0000-0000-0000-000000000000', 0) 
, ('AFE10CEE-EB74-4A7F-BA78-B58F73DE4B58', 'Muskellunge, Tiger', 'Esox lucius x E. masquinongy', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 2) 
, ('F0779165-C57C-4791-9639-B59E441EB281', 'Chub, Bluehead', 'Nocomis leptocephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('7BD23CE1-35E6-4112-91CF-B5C432FA11C0', 'Darter, Bridled', 'Percina kusha', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('909B1FDF-A21D-4C1B-890C-B637149D7DF2', 'Darter, Arrow', 'Etheostoma sagitta', '00000000-0000-0000-0000-000000000000', 0) 
, ('5028A5E6-DAA9-4039-B070-B64DE09AD2EB', 'Trout, Bull', 'Salvelinus confluentus', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('55CDAD1D-5811-4C50-910D-B669D317A591', 'Chub, Bigmouth', 'Nocomis platyrhynchus', '00000000-0000-0000-0000-000000000000', 0) 
, ('047A1ACA-0F70-45FD-940A-B6ABE9907770', 'Trout-perch', 'Percopsis omiscomaycus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('073CD69E-D9F4-4377-A746-B6F32CB9E3BA', 'Crappie, White', 'Pomoxis annularis', '00000000-0000-0000-0000-000000000000', 0) 
, ('95257A84-67C5-40EA-9948-B799F6D028CC', 'Hitch', 'Lavinia exilicauda', '00000000-0000-0000-0000-000000000000', 0) 
, ('02AC412B-3106-4B9C-8F19-B7E2E45BC787', 'Darter, Bluemask', 'Etheostoma akatulo', '00000000-0000-0000-0000-000000000000', 0) 
, ('B25DDB54-6F1E-4EF7-AFC3-B7ECA3853CE1', 'Lamprey, Pacific', 'Lampetra tridentata', '00000000-0000-0000-0000-000000000000', 0) 
, ('E19B04F8-2749-4D33-BB84-B7F45F4BB739', 'Chub, Blue', 'Gila coerulea', '00000000-0000-0000-0000-000000000000', 0) 
, ('548D5B28-DD89-49C0-BBCF-B8217EEBF31D', 'Perch, Pirate', 'Aphredoderus sayanus', '9D2613FF-D6CE-42E8-B9A4-A778A9E580FE', 0) 
, ('5C0F61C0-7C3C-4093-B07C-B882CC010D5F', 'Cisco, Bonneville', 'Prosopium gemmifer', '00000000-0000-0000-0000-000000000000', 0) 
, ('082A8B39-6EC4-48B2-B0AF-B94EE20E871C', 'Eulachon', 'Thaleichthys pacificus', '00000000-0000-0000-0000-000000000000', 0) 
, ('74DDA9B7-2EC6-4462-8194-B99B90F15340', 'Darter, Tombigbee', 'Etheostoma lachneri', '00000000-0000-0000-0000-000000000000', 0) 
, ('5F151B6F-AFCF-45A7-926F-B9B96435E8E6', 'Acadian redfish', 'Sebastes fasciatus', '9F5E0B5F-40EC-4565-8FF6-224EC88FBD40', 0) 
, ('BF124AED-250E-48B0-9556-B9FE88BADAA0', 'Shiner, Yazoo', 'Notropis rafinesquei', '00000000-0000-0000-0000-000000000000', 0) 
, ('9DBD22AE-A22D-483A-A868-BA3E5692A9E3', 'Madtom, Orangefin', 'Noturus gilberti', '00000000-0000-0000-0000-000000000000', 0) 
, ('A5B77BCF-37E7-4A51-80A8-BAB9CEE69174', 'Salmon, Kokanee', 'Oncorhynchus nerka', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('05022468-64F9-41F6-A36F-BB08EE8EBBBD', 'Ruffe', 'Gymnocephalus cernuus', '00000000-0000-0000-0000-000000000000', 0) 
, ('94F27CB4-40AF-4FCD-A41F-BB1CED604EAF', 'Spinedace, White River', 'Lepidomeda albivallis', '00000000-0000-0000-0000-000000000000', 0) 
, ('B6933F7F-3AC7-4A87-9C43-BBB33447D71D', 'Darter, Pinewoods', 'Etheostoma mariae', '00000000-0000-0000-0000-000000000000', 0) 
, ('D9A5BD57-C392-4E9C-8572-BBF174BD6A32', 'Pumpkinseed Sunfish', 'Lepomis gibbosus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('780F6682-7A52-4BF3-86A8-BD61AF32ABBB', 'Shiner, Coosa', 'Notropis xaenocephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B6EF1119-BC95-4B8C-9890-BD72FE1948A7', 'Lamprey, Sea', 'Petromyzon marinus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 16) 
, ('D3105EF2-3A9E-4832-9050-BE00A0B2FAF9', 'Turbot', 'Scophthalmus maximus', '7221E9ED-899A-48EB-8947-9DE1A9A8EF59', 0) 
, ('0469FEBD-9816-48B8-87BF-BEB3A5F65E19', 'Dace, Moapa', 'Moapa coriacea', '00000000-0000-0000-0000-000000000000', 0) 
, ('05A37244-029C-4735-A5CC-BED56BF03FAA', 'Goby, Blotchcheek', 'Ctenogobius fasciatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('A23726A9-91E5-4ED7-B7B3-BEE6689B6975', 'Sunfish, Bantam', 'Lepomis symmetricus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E6999C5C-559E-4367-92EB-BEFAC69E9058', 'Madtom, Northern', 'Noturus stigmosus', '00000000-0000-0000-0000-000000000000', 0) 
, ('47EDAE58-D888-43C0-8B73-BFBF867DCD9D', 'Darter, Chainback', 'Percina nevisense', '00000000-0000-0000-0000-000000000000', 0) 
, ('101968BA-389D-446E-A4D4-BFDE6792B125', 'Atlantic Needlefish', 'Strongylura marina', '00000000-0000-0000-0000-000000000000', 0) 
, ('99C7C368-BCA1-4608-8CAA-C05DEE53AC25', 'Bass, Rock', 'Ambloplites rupestris', '40605545-00AF-455D-8868-8F1546D3DB72', 1) 
, ('99DDA454-AD81-4D51-A12D-C0710A3FB7D6', 'Clear Lake Splittail', 'Pogonichthys ciscoides', '00000000-0000-0000-0000-000000000000', 0) 
, ('0F453BA8-F41B-48A9-B1F5-C08DC2856FDA', 'Redhorse, Silver', 'Moxostoma anisurum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('25D66B01-EAD5-4B2F-8167-C0C3F47EBAF9', 'Dace, Finescale CN', 'Chrosomus neogaeus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 23) 
, ('7B352106-07BD-4A4F-85B4-C16BED9E6708', 'Chub, Yaqui', 'Gila purpurea', '00000000-0000-0000-0000-000000000000', 0) 
, ('DC3EDDCE-19FC-40CB-85A4-C1940C7FA321', 'Cisco, Shortnose', 'Coregonus reighardi', '00000000-0000-0000-0000-000000000000', 0) 
, ('1586574F-BB01-476D-A20F-C1E6CBB268EB', 'Chub, Highback', 'Hybopsis hypsinotus', '00000000-0000-0000-0000-000000000000', 0) 
, ('6B45FEA3-5CBE-4982-89AF-C241EB5C6A36', 'Smelt, Rainbow', 'Osmerus mordax', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('F403F0D1-37F1-4116-A7A8-C2538A033773', 'Shiner, Blacktip', 'Lythrurus atrapiculus', '00000000-0000-0000-0000-000000000000', 0) 
, ('317B5231-C64F-4C05-9AD0-C29CED760C58', 'Darter, Striated', 'Etheostoma striatulum', '00000000-0000-0000-0000-000000000000', 0) 
, ('D2ACFA5F-1682-445D-B7B4-C29DD1F3E975', 'Darter, Naked Sand', 'Ammocrypta beanii', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('4DB64C3D-95CC-4E19-85BE-C2A46582F813', 'Bass, Spotted', 'Micropterus punctulatus', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('B1976234-DD81-46B8-AAF1-C323E865EF49', 'Goby, Round', 'Neogobius melanostomus', '00000000-0000-0000-0000-000000000000', 4) 
, ('F21A136A-9A07-41DE-8F3E-C32CF50D0F08', 'Molly, Amazon', 'Poecilia formosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('D441C39C-2D3D-41D2-B978-C335C25CA1FB', 'Shiner, Redside', 'Richardsonius balteatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('CF115C16-08FB-4190-AA8C-C3433709A804', 'Poolfish, Pahrump', 'Empetrichthys latos', '00000000-0000-0000-0000-000000000000', 0) 
, ('9DCFFB68-8971-4FE4-BB52-C37CFD32B303', 'Logperch, Mobile', 'Percina kathae', '00000000-0000-0000-0000-000000000000', 0) 
, ('16283FE1-4F6A-4C80-9E55-C38898B1C880', 'Darter, Florida Sand', 'Ammocrypta bifascia', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('7C4FA340-D964-48CA-8FE6-C388E724C41B', 'Shiner, Emerald', 'Notropis atherinoides', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('DFB8CE75-1782-4B5E-83D2-C3BF9141E26D', 'Peamouth', 'Mylocheilus caurinus', '00000000-0000-0000-0000-000000000000', 0) 
, ('3527AF30-C67B-406D-9BD2-C3EF7CE5F362', 'Minnow, Rio Grande Silvery', 'Hybognathus amarus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('EBFAA11F-FC95-4D01-A0EE-C4854DCD88E6', 'Darter, Tippecanoe', 'Etheostoma tippecanoe', '00000000-0000-0000-0000-000000000000', 0) 
, ('F4951953-5540-45BB-A4B7-C4E19C92ED6B', 'Sheepshead', 'Archosargus probatocephalus', 'F8814898-7C27-4840-AE2F-437517D014A9', 0) 
, ('9AEB7A77-A44E-4995-9135-C546861B476D', 'Darter, Goldstripe', 'Etheostoma parvipinne', '00000000-0000-0000-0000-000000000000', 0) 
, ('FF28590A-363A-442B-A0EB-C57214895228', 'Darter, Bronze', 'Percina palmaris', '00000000-0000-0000-0000-000000000000', 0) 
, ('6F1B6805-C1C6-46AE-8C49-C5BE062322E0', 'Topminnow, Whiteline', 'Fundulus albolineatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('EBFE3D66-A1C2-458F-BA4D-C654196BE990', 'Minnow, Tonguetied', 'Exoglossum laurae', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('F00823DF-25DA-4B3D-93EF-C658EE9EF302', 'Lamprey, Northern Brook', 'Ichthyomyzon fossor', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('4090AAA5-BBB0-4A02-A27D-C6F5BEC0F4CE', 'Darter, Cherry', 'Etheostoma etnieri', '00000000-0000-0000-0000-000000000000', 0) 
, ('1A7F1E20-5B41-471A-9788-C750901E0D0C', 'Cisco, Nipigon', 'Coregonus nipigon', '00000000-0000-0000-0000-000000000000', 2) 
, ('93802B96-F120-4CAC-A60D-C750A275ABD6', 'Shiner, Satinfin', 'Notropis analostanus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('B68FA356-70B9-4A7C-89BC-C7ADAE4DF15B', 'Shiner, Spotfin', 'Cyprinella spiloptera', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('4E8FDE4B-DAB2-4B7F-B669-C83360B72AE6', 'Rio Grande Cichlid', 'Cichlasoma cyanoguttatum', 'BF791321-53FE-4C3C-8914-12ECB684B6C6', 0) 
, ('E4B7F50D-B108-4858-868F-C8D6877EABBC', 'Sculpin, Slimy', 'Cottus cognatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('D7737A68-5DAF-4126-B5EC-C9583C611FE5', 'Flagfish', 'Jordanella floridae', '00000000-0000-0000-0000-000000000000', 0) 
, ('D6F9478F-C16A-46D7-9C5D-C9F62AD34CA8', 'Perch, Shiner', 'Cymatogaster aggregata', '71CB46FC-E054-4031-BFCF-5485E71259A5', 0) 
, ('1D4799E1-F33D-4F51-B7DF-CB13676DB450', 'Sucker, Owens', 'Catostomus fumeiventris', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('E8B6B920-8AA5-4653-BEBC-CB238667B09A', 'Carp, Bighead', 'Hypophthalmichthys nobilis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 1) 
, ('AE6D1E63-E066-442B-B0E3-CB37B804DBB0', 'Mudminnow, Central', 'Umbra limi', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('420994F7-6B2B-41CA-BEDB-CB80DE93EF79', 'Darter, Appalachia', 'Percina gymnocephala', '00000000-0000-0000-0000-000000000000', 0) 
, ('8EFEB62F-16B5-4D1F-8776-CBC4D8A46A5B', 'Lamprey, Modoc Brook', 'Lampetra folletti', '00000000-0000-0000-0000-000000000000', 0) 
, ('B6974722-628B-45ED-9BE0-CBCC33A1D55D', 'Kiyi', 'Coregonus kiyi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D3A8DDEE-0A8F-4338-929B-CBEB4BC67400', 'Shiner, Longnose', 'Notropis longirostris', '00000000-0000-0000-0000-000000000000', 0) 
, ('D6E7FB4A-D97A-4A28-9BA7-CBF4EF37CEA5', 'Mosquitofish, Eastern', 'Gambusia holbrooki', '00000000-0000-0000-0000-000000000000', 0) 
, ('E9B8CEFD-D5D5-443B-9C19-CCA7D0B9292D', 'Mudminnow, Eastern', 'Umbra pygmaea', '00000000-0000-0000-0000-000000000000', 0) 
, ('86C0BBBC-5E60-4FAC-B385-CCD4F4EB8D55', 'Darter, Coldwater', 'Etheostoma ditrema', '00000000-0000-0000-0000-000000000000', 0) 
, ('4115144B-2BC5-4B55-A863-CD250FD988BC', 'Smelt, Pygmy', 'Osmerus spectrum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('96F0F39F-7AB3-4586-8A64-CDD773CCB635', 'Shiner, Yellowfin', 'Notropis lutipinnis', '00000000-0000-0000-0000-000000000000', 0) 
, ('89C59FE6-66A1-4B7B-A835-CE0724557272', 'Shiner, Orangefin', 'Notropis ammophilus', '00000000-0000-0000-0000-000000000000', 0) 
, ('EF0EC18C-5A09-4CD9-A0EA-CE7D8C98EBC7', 'Shiner, Plateau', 'Cyprinella lepida', '00000000-0000-0000-0000-000000000000', 0) 
, ('63AA74E9-6D27-496E-9C53-CEF63919580C', 'Whitefish, Spotted', 'Prosopium sp. 1', '00000000-0000-0000-0000-000000000000', 0) 
, ('A85EBF22-4AB9-4A91-A14A-CEF6C8E64D97', 'Bass, Largemouth', 'Micropterus salmoides', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('F74FDB76-AA4B-4666-9E66-CF35FE7517F4', 'Sculpin, Shorthead', 'Cottus confusus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('7DFA6D1E-13D9-45D0-88C3-CF93E499FE4A', 'Lamprey, Southern Brook', 'Ichthyomyzon gagei', 'F444C6BF-44A7-4419-8624-DF152DAD37D8', 32) 
, ('892F92EF-0976-4791-BEB3-CFF63401F70C', 'Shiner, Ghost', 'Notropis buchanani', '00000000-0000-0000-0000-000000000000', 4) 
, ('52667DBA-6552-4418-91E4-D06B27779E3F', 'Dace, Redbelly Northern', 'Chrosomus eos', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('D6C49359-9069-4A2F-89EA-D07624F78074', 'Minnow, Riffle', 'Phenacobius catostomus', '00000000-0000-0000-0000-000000000000', 0) 
, ('1048042B-880D-4F9F-8CD3-D0EF2EC9D185', 'Darter, Stripetail', 'Etheostoma kennicotti', '00000000-0000-0000-0000-000000000000', 0) 
, ('B176A99E-2C14-4DE2-B607-D184392B1FDD', 'Sucker, Warner', 'Catostomus warnerensis', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('518AF43C-A0F4-44E4-8817-D2441354A140', 'Minnow, Fatlips', 'Phenacobius crassilabrum', '00000000-0000-0000-0000-000000000000', 0) 
, ('CC608C7B-3B01-47F2-B36B-D26DD1DFDADC', 'Sturgeon, Gulf', 'Acipenser oxyrinchus desotoi', '00000000-0000-0000-0000-000000000000', 32) 
, ('1FB7BDD9-0F07-4714-BD00-D2724CBBF9F1', 'Sucker, Shortnose', 'Chasmistes brevirostris', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('B3FCFFAB-CBA7-4647-A901-D2D578ACD7D3', 'Char, Arctic', 'Salvelinus alpinus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('9102E24A-1240-4BB3-95E8-D3244B59549C', 'Shiner, Pugnose', 'Notropis anogenus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('681351AE-8ED4-4E8E-9686-D338D3B02163', 'Darter, Current', 'Etheostoma uniporum', '00000000-0000-0000-0000-000000000000', 0) 
, ('7EF11833-386A-4B0D-A44D-D3DC648ADF97', 'Redhorse, Slender', 'Moxostoma pappillosum', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('F633630D-4F07-4D97-BC86-D445D8B5254F', 'Pikeminnow, Northern', 'Ptychocheilus oregonensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('DE64728A-D101-43C4-A5D1-D47B321E1804', 'Catfish, White', 'Ameiurus catus', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 0) 
, ('2449BC30-B1C0-4B66-9DAD-D484D1AD6356', 'Sunfish, Spotted', 'Lepomis punctatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('B5593AE2-568E-47B3-A0E1-D4936BB45B27', 'Catfish, Flathead', 'Pylodictis olivaris', '00000000-0000-0000-0000-000000000000', 1) 
, ('78AB00A1-A6B1-4EEA-A792-D4AEB26E58B8', 'Shiner, Sand', 'Notropis stramineus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('50045A83-B1D1-4AAB-B72C-D4E82867B903', 'Shiner, New River', 'Notropis scabriceps', '00000000-0000-0000-0000-000000000000', 0) 
, ('C7D5F9C6-4967-4FFA-8131-D687F489781B', 'Purple Atacama Snailfish', 'Elassodiscus tremebundus', '809839D3-285E-4E2D-A4C5-EC6993273F22', 0) 
, ('BF306375-4830-477B-8AAE-D6B2EB938303', 'Redhorse, Black', 'Moxostoma duquesnei', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('12F3BE54-96A8-4459-BBD8-D6F4828CFD25', 'Percina antesella', 'Amber Darter', '00000000-0000-0000-0000-000000000000', 0) 
, ('9612F721-AB7F-4A5A-9EEF-D720D9D3D2D1', 'Sturgeon, Green', 'Acipenser medirostris', '7CBAFEAB-6B52-469B-AC47-F24F5F64C80E', 3) 
, ('5FF89422-185C-4CCD-9474-D72D18B5A640', 'Goby, Naniha', 'Stenogobius hawaiiensis', '00000000-0000-0000-0000-000000000000', 0) 
, ('A3C773CA-6665-42D2-8241-D74A2F605811', 'Killifish, Seminole', 'Fundulus seminolis', '00000000-0000-0000-0000-000000000000', 0) 
, ('03218BCB-6400-46F8-AD83-D7C981F548FE', 'Sunfish, Carolina Pygmy', 'Elassoma boehlkei', '00000000-0000-0000-0000-000000000000', 0) 
, ('76F0E637-CA47-44C2-BBFE-D80E3F6AEE5A', 'Darter, Lollypop', 'Etheostoma neopterum', '00000000-0000-0000-0000-000000000000', 0) 
, ('C0F1008B-4315-4FFF-8EA9-D822DBF2BC47', 'Darter, Bluebreast', 'Etheostoma camurum', '00000000-0000-0000-0000-000000000000', 0) 
, ('1AFC6D72-06AE-4FCD-8A27-D8892CA15A57', 'Madtom, Ozark', 'Noturus albater', '00000000-0000-0000-0000-000000000000', 0) 
, ('EA66E428-6665-4A71-95A2-D892D33127FE', 'Cisco, Blackfin', 'Coregonus nigripinnis', '00000000-0000-0000-0000-000000000000', 4) 
, ('84EF1B92-4D63-405D-B9A4-D8B135FB725C', 'Broad whitefish', 'Coregonus nasus', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 0) 
, ('4BE6018B-6363-43E2-8EF6-D92C381125DA', 'Darter, Arkansas Saddled', 'Etheostoma euzonum', '00000000-0000-0000-0000-000000000000', 0) 
, ('716EB5B4-6427-4901-9538-D94C3282E380', 'Bass, Striped', 'Morone saxatilis', '338BFB26-A2C0-4216-BDE4-9ED8587996FE', 1) 
, ('37EF8105-1F6E-4282-A055-D98313E84C44', 'Shiner, Smalleye', 'Notropis buccula', '00000000-0000-0000-0000-000000000000', 0) 
, ('9C834B0A-4495-49C0-BF8A-D9A9DB4C154B', 'Chub, Borax Lake', 'Gila boraxobius', '00000000-0000-0000-0000-000000000000', 0) 
, ('DE4E26F2-D08F-4B1E-B5F9-DA0EB63B3718', 'Redhorse, Greater', 'Moxostoma valenciennesi', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('97FEB537-979A-44C2-9200-DA317EC8D755', 'Dace, Las Vegas', 'Rhinichthys deaconi', '00000000-0000-0000-0000-000000000000', 0) 
, ('FBE3AF76-99AB-4BA1-92AD-DA662CD52BF8', 'Madtom, Checkered', 'Noturus flavater', '00000000-0000-0000-0000-000000000000', 0) 
, ('42C05230-6F15-478F-8937-DAA46BEDC04E', 'Pikeminnow, Umpqua', 'Ptychocheilus umpquae', '00000000-0000-0000-0000-000000000000', 0) 
, ('7544AA08-5CDB-4FBA-98FA-DABF738FEB61', 'Minnow, Bluntnose', 'Pimephales notatus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('59D25A07-BACE-45FF-9070-DB311365DDEE', 'Sculpin, Mottled', 'Cottus bairdii', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('9A3D339A-1CFD-47B6-8467-DB804E18F5B4', 'Shiner, Ocmulgee', 'Cyprinella callisema', '00000000-0000-0000-0000-000000000000', 0) 
, ('78EBD000-F988-4D4C-A229-DB86558C00EE', 'Shiner, Blackspot', 'Notropis atrocaudalis', '00000000-0000-0000-0000-000000000000', 0) 
, ('45EC6E97-EB07-4F0A-B4FE-DC2D08710E83', 'Stoneroller, Mexican', 'Campostoma ornatum', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('DCDC15FD-EA9A-4551-97B9-DD0053850D5E', 'Chub, Sandhills', 'Semotilus lumbee', '00000000-0000-0000-0000-000000000000', 0) 
, ('2304D3AB-C513-4F01-815F-DD540CD23EFB', 'Shiner, Saffron', 'Notropis rubricroceus', '00000000-0000-0000-0000-000000000000', 0) 
, ('D41DF919-B500-476C-9D23-DEDFE3D429C1', 'Shiner, Blackchin', 'Notropis heterodon', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('2C98075F-FEE8-4677-B740-DEF406CBE2FB', 'Spikedace', 'Meda fulgida', '00000000-0000-0000-0000-000000000000', 0) 
, ('DD3F141E-5A1C-4D89-90B1-DF160BB27E56', 'Darter, Blenny', 'Etheostoma blennius', '00000000-0000-0000-0000-000000000000', 0) 
, ('7E2BEC38-B4AB-4E4C-AB6F-DF4270AD74BA', 'Sculpin, Paiute', 'Cottus beldingii', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('C2B35206-DDD8-416F-A9EE-DFF93DC7A34D', 'Bullhead, Black', 'Ameiurus melas', '00000000-0000-0000-0000-000000000000', 0) 
, ('5FA157CE-43F4-4CD2-BB35-E0682B82589F', 'Darter, Eastern Sand', 'Ammocrypta pellucida', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('3EE302E7-C9BB-4214-BFFA-E06D9B41E0A6', 'Shiner, Ironcolor', 'Notropis chalybaeus', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('26E83FB0-3183-4A26-B8C1-E0FEFC3A5104', 'Darter, Rush', 'Etheostoma phytophilum', '00000000-0000-0000-0000-000000000000', 0) 
, ('2AA4DD45-3C70-4E9E-AFE0-E1177E7FFFF7', 'Darter, Missouri Saddled', 'Etheostoma tetrazonum', '00000000-0000-0000-0000-000000000000', 0) 
, ('3640D593-4491-4C9D-A440-E1D28B48DB30', 'Darter, Dusky', 'Percina sciera', '00000000-0000-0000-0000-000000000000', 0) 
, ('C3A994BB-D2EB-4B96-BA50-E1F81F5DC35D', 'Darter, Channel', 'Percina copelandi', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('0FB8BA7C-AD88-4ACE-A633-E2225BC5D5C7', 'Darter, Fantail', 'Etheostoma flabellare', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('55100729-F6AE-4CE0-B702-E2403E392641', 'Buffalo, Black', 'Ictiobus niger', '00000000-0000-0000-0000-000000000000', 0) 
, ('F3A6D72D-8507-44E7-A750-E28904764DA8', 'Minnow, Kanawha', 'Phenacobius teretulus', '00000000-0000-0000-0000-000000000000', 0) 
, ('04942E64-9013-4E5A-A07F-E291CA9DE52F', 'Chub, Silver', 'Macrhybopsis storeriana', '00000000-0000-0000-0000-000000000000', 0) 
, ('263FB303-3D34-431B-82BF-E29FA1A628CE', 'Darter, Slabrock', 'Etheostoma smithi', '00000000-0000-0000-0000-000000000000', 0) 
, ('7A7FA636-9957-4287-9892-E2D003A006C3', 'California Roach', 'Lavinia symmetricus', '00000000-0000-0000-0000-000000000000', 0) 
, ('0CCAF204-8618-4B18-A0B4-E2F85C6737AC', 'Mooneye', 'Hiodon tergisus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 16) 
, ('3CCC341D-E717-4A8D-95BA-E326DEAA39A3', 'Shiner, Whitefin', 'Cyprinella nivea', '00000000-0000-0000-0000-000000000000', 0) 
, ('BD6E2615-ADCC-4FFD-8870-E3B579BE8D91', 'Sturgeon', 'Acipenserinae', '00000000-0000-0000-0000-000000000000', 1) 
, ('FABBE614-8569-4F27-AD89-E4CCD5EEED5D', 'Darter, Riverweed', 'Etheostoma podostemone', '00000000-0000-0000-0000-000000000000', 0) 
, ('BE69A534-CB7D-4751-9B7D-E4F54873B5CF', 'Swampfish', 'Chologaster cornuta', 'B3B6FD5A-DB37-4AFA-B94D-EFC7C93C6A5C', 0) 
, ('3ECF0BA1-6FC8-433F-8BFC-E50DB1022FF7', 'Darter, Spotted', 'Etheostoma maculatum', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 0) 
, ('235A9B05-5DA7-4334-AA5A-E5A003FF5032', 'Shiner, Skygazer', 'Notropis uranoscopus', '00000000-0000-0000-0000-000000000000', 0) 
, ('301B4E85-CB63-4157-9161-E5E371358438', 'Chub, Rio Grande', 'Gila pandora', '00000000-0000-0000-0000-000000000000', 0) 
, ('8DD1CE09-9C46-44E9-A3F6-E627393B850B', 'Chub, Shoal', 'Macrhybopsis hyostoma', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('0265BF5E-F88A-4932-8439-E64185CB1FA7', 'Darter, Coppercheek', 'Etheostoma aquali', '00000000-0000-0000-0000-000000000000', 0) 
, ('4059CAED-0E1D-48C7-B4ED-E66DB733CB88', 'Killifish, Least', 'Heterandria formosa', '00000000-0000-0000-0000-000000000000', 0) 
, ('BF0F5FF8-D546-42FC-88D1-E6A53E632D5A', 'Carpsucker, Highfin', 'Carpiodes velifer', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('721F515C-D812-4E6A-ABF8-E77E41DE4EB7', 'Gambusia, San Felipe', 'Gambusia clarkhubbsi', '00000000-0000-0000-0000-000000000000', 0) 
, ('B01D7F21-30A7-4309-BCA1-E830DD9D7A41', 'Sculpin, Coastrange', 'Cottus aleuticus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('ADC78605-889B-4465-AE76-E8530CCC483C', 'Buffalo, Smallmouth', 'Ictiobus bubalus', '00000000-0000-0000-0000-000000000000', 16) 
, ('094CC56A-5F61-42A6-8720-E857435137F0', 'Gambusia, San Marcos', 'Gambusia georgei', '00000000-0000-0000-0000-000000000000', 0) 
, ('898ABF94-0C6D-44D9-B48D-E869BBB74FE2', 'Flat Bullhead', 'Ameiurus platycephalus', '941775A2-A9E1-4759-8559-17B15DB6DE7A', 0) 
, ('10A3CA7C-4633-4F76-B544-E8809ED5542A', 'Blindcat, Widemouth', 'Satan eurystomus', '00000000-0000-0000-0000-000000000000', 0) 
, ('4F023204-CDAF-4FAE-BF7F-E9319794E8FF', 'Carp, Common', 'Cyprinus carpio', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('E8CF6FAA-3DE9-4B03-B002-E93AACDFCD62', 'Shiner, Silver', 'Notropis photogenis', '00000000-0000-0000-0000-000000000000', 0) 
, ('5580E102-F717-4420-9BCF-E99D8E22DA7F', 'Shiner, Proserpine', 'Cyprinella proserpina', '00000000-0000-0000-0000-000000000000', 0) 
, ('096B01FE-C8BA-42C2-9DBA-EA5DC5290AFD', 'Darter, Slackwater', 'Etheostoma boschungi', '00000000-0000-0000-0000-000000000000', 0) 
, ('D231B5E9-75A4-4CA7-B7BE-EABB4781839E', 'Darter, Coastal', 'Etheostoma colorosum', '00000000-0000-0000-0000-000000000000', 0) 
, ('A19C328E-1563-4772-8D1B-EAFA65E656DA', 'Darter, Swannanoa', 'Etheostoma swannanoa', '00000000-0000-0000-0000-000000000000', 0) 
, ('3CBDB5EE-EE1A-4A39-AA3F-EB2E755E8319', 'Minnow, Slim', 'Pimephales tenellus', '00000000-0000-0000-0000-000000000000', 0) 
, ('E9EB860A-F416-4E7E-B34D-EB35D12F7503', 'Sacramento Blackfish', 'Orthodon microlepidotus', '00000000-0000-0000-0000-000000000000', 0) 
, ('0BA2501A-A305-4920-8415-EC56F98A2E96', 'Pallid Sturgeon', 'Scaphirhynchus albus', '00000000-0000-0000-0000-000000000000', 0) 
, ('F4D6CC77-DE58-4614-9CFD-EC7BA3495FF1', 'Chub, Ozark', 'Erimystax harryi', '00000000-0000-0000-0000-000000000000', 0) 
, ('2946A8DB-882A-4075-B4B4-EC88D3467239', 'Madtom, Saddled', 'Noturus fasciatus', '00000000-0000-0000-0000-000000000000', 0) 
, ('BD7BC4E9-6CAB-41D2-ADDA-EC9F86165D40', 'Redhorse, Gray', 'Moxostoma congestum', '00000000-0000-0000-0000-000000000000', 0) 
, ('148EFA52-CA3E-4DB0-BECE-ECC8F37659C4', 'Shiner, Rosyface', 'Notropis rubellus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('D67C0E19-4BDD-4968-A756-EE38D274AFAC', 'Goby, Mexican', 'Ctenogobius claytonii', '00000000-0000-0000-0000-000000000000', 0) 
, ('8814BFF9-AE02-44B0-87B8-EE69AB036010', 'Redhorse, Shorthead', 'Moxostoma macrolepidotum', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 32) 
, ('E98D1C80-1B7C-4321-A4C7-EEA14591A3A9', 'Studfish, Stippled', 'Fundulus bifax', '00000000-0000-0000-0000-000000000000', 0) 
, ('1FCE82D1-F805-49BB-A85A-EEC8CD240ED0', 'Darter, Rainbow', 'Etheostoma caeruleum', '00000000-0000-0000-0000-000000000000', 0) 
, ('0CD0D130-2249-4EE2-8AB6-EED15107142D', 'Chum Salmon', 'Oncorhynchus keta', '00000000-0000-0000-0000-000000000000', 0) 
, ('5A4169A1-2859-4CB8-B80C-EEFDA6A5A032', 'Goby, Tidewater', 'Eucyclogobius newberryi', '00000000-0000-0000-0000-000000000000', 0) 
, ('54FB4D7C-55A3-4B22-9290-EF7D289E4022', 'Bay Anchovy', 'Anchoa mitchilli', 'D83A137B-EC51-4B04-8F69-F8ED716D22F5', 0) 
, ('27A88405-B318-4897-94B6-F005B44C9390', 'Minnow, Mississippi Silvery', 'Hybognathus nuchalis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 32) 
, ('904FEA57-4277-4ACC-9953-F0EFF7AFC74C', 'Darter, Blueside', 'Etheostoma jessiae', '00000000-0000-0000-0000-000000000000', 0) 
, ('871CA4A8-075B-4FBB-BBF1-F1083E3FC85A', 'Darter, Tangerine', 'Percina aurantiaca', '00000000-0000-0000-0000-000000000000', 0) 
, ('69CBA681-3741-496F-A654-F15F66C123C0', 'Northern Redhorse', 'Moxostoma aureolum', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('114D7D9C-21AE-4469-A400-F1C85993FCD5', 'Shiner, Blacktail', 'Cyprinella venusta', '00000000-0000-0000-0000-000000000000', 0) 
, ('90B340F6-57D6-4C77-B434-F21A83C370ED', 'Darter, Coal', 'Percina brevicauda', '00000000-0000-0000-0000-000000000000', 0) 
, ('1153EC8F-FFF8-49BB-8B23-F2E9B775B27E', 'Zander', 'Sander lucioperca', '00000000-0000-0000-0000-000000000000', 32) 
, ('2F9C392E-9A69-47F7-B6AB-F320AE62B672', 'Sculpin, Reticulate', 'Cottus perplexus', 'D4A8B0ED-65A9-4CB4-9B3C-282FC777436A', 0) 
, ('0A2A5C69-004E-449B-B32B-F3538BDE5DB1', 'Sleeper, Largescaled Spinycheek', 'Eleotris amblyopsis', '00000000-0000-0000-0000-000000000000', 0) 
, ('6D1DC7F4-DBAD-401F-9D77-F375A5F19809', 'Chub, Clear', 'Hybopsis winchelli', '00000000-0000-0000-0000-000000000000', 0) 
, ('63F532A9-F02D-4C80-AFFE-F3883880297B', 'Lamprey, Klamath', 'Lampetra similis', '00000000-0000-0000-0000-000000000000', 0) 
, ('E36E99D6-4B43-420A-9560-F39A2E56F84D', 'Jumprock, Striped', 'Moxostoma rupiscartes', '00000000-0000-0000-0000-000000000000', 0) 
, ('D31D2D0B-7462-4EF9-8BF3-F3A142544965', 'Killifish, Bluefin', 'Lucania goodei', '00000000-0000-0000-0000-000000000000', 0) 
, ('3B626F60-BDE0-4DDA-8734-F40AB0DACEDC', 'Pikeminnow, Colorado', 'Ptychocheilus lucius', '00000000-0000-0000-0000-000000000000', 0) 
, ('E2F89885-562A-497D-87F5-F42117537704', 'Chub, Flame', 'Hemitremia flammea', '00000000-0000-0000-0000-000000000000', 0) 
, ('5896736D-4414-44F3-B122-F43269128F8D', 'Killifish, Pygmy', 'Leptolucania ommata', '00000000-0000-0000-0000-000000000000', 0) 
, ('54B17449-0165-4AE3-BE46-F46A980DAFF7', 'Shiner, White', 'Luxilus albeolus', '00000000-0000-0000-0000-000000000000', 0) 
, ('3BADEF57-16C6-415C-B16C-F54D54F1D722', 'Shiner, Bigmouth', 'Notropis dorsalis', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('9F98AA7C-6960-42FF-BD26-F54D781CD729', 'Shiner, Tallapoosa', 'Cyprinella gibbsi', 'D664EB73-BCAF-4ED2-803E-20DF79BB8051', 0) 
, ('AE419329-B91E-497F-8E5C-F5649BDE57D0', 'Chub, Lined', 'Hybopsis lineapunctata', '00000000-0000-0000-0000-000000000000', 0) 
, ('6F16977A-633C-498B-8796-F56FFD2ABEB5', 'Darter, Backwater', 'Etheostoma zonifer', '00000000-0000-0000-0000-000000000000', 0) 
, ('0DF6B509-92F1-412E-9F09-F58723202EBF', 'Darter, River', 'Percina shumardi', '00000000-0000-0000-0000-000000000000', 0) 
, ('C2D873DD-1038-46C0-B50B-F5A2F75AAE9F', 'Perch, Tule', 'Hysterocarpus traskii', '00000000-0000-0000-0000-000000000000', 0) 
, ('9D4F5135-83E2-4E4C-A3BF-F5AC3AB3BD9F', 'Chub, Redeye', 'Notropis harperi', '00000000-0000-0000-0000-000000000000', 0) 
, ('0DEFB429-1F3E-46DE-AC3D-F5C7886A1043', 'Spinedace, Virgin', 'Lepidomeda mollispinis', '00000000-0000-0000-0000-000000000000', 0) 
, ('89DA530C-7107-4765-82D1-F681DFFE9060', 'Shiner, Burrhead', 'Notropis asperifrons', '00000000-0000-0000-0000-000000000000', 0) 
, ('4D7C838C-53BD-4DAC-9D79-F69573BE43B7', 'Lamprey, Pit-klamath Brook', 'Lampetra lethophaga', '00000000-0000-0000-0000-000000000000', 0) 
, ('AD249B10-646E-4A32-BD39-F7B0C93E2F44', 'Darter, Gilt', 'Percina evides', '00000000-0000-0000-0000-000000000000', 0) 
, ('774ABCFB-35A2-45B4-9BAE-F80B5FF8DE66', 'Poolfish, Ash Meadows', 'Empetrichthys merriami', '00000000-0000-0000-0000-000000000000', 0) 
, ('540BAD1C-64DB-41EC-9ADC-F81498F02805', 'Shiner, Greenhead', 'Notropis chlorocephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('3484B516-CFE8-4DD5-BE13-F83733B3159C', 'Bass, Ozark', 'Ambloplites constellatus', '40605545-00AF-455D-8868-8F1546D3DB72', 0) 
, ('15B89758-C31C-4FF1-BD1F-F862D360E520', 'Killifish, Speckled', 'Fundulus rathbuni', '00000000-0000-0000-0000-000000000000', 0) 
, ('68E311B4-55AA-471E-9F6C-F8767C0FF28E', 'Darter, Pearl', 'Percina aurora', '00000000-0000-0000-0000-000000000000', 0) 
, ('2751C012-5F9B-4E29-B3A3-F8CC133C7066', 'Darter, Banded', 'Etheostoma zonale', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('A1F763C4-4265-4D0A-88CF-F9C75D7F5FBD', 'Darter, Candy', 'Etheostoma osburni', '00000000-0000-0000-0000-000000000000', 0) 
, ('7788F4F0-AB2A-41E0-9DD8-F9CFED21CA91', 'Lamprey, Least Brook', 'Lampetra aepyptera', '00000000-0000-0000-0000-000000000000', 0) 
, ('743F9D73-3543-434D-88BC-F9F1E6FD639B', 'Shiner, Roughhead', 'Notropis semperasper', '00000000-0000-0000-0000-000000000000', 0) 
, ('42C85A11-BEFE-40D5-AD04-FA6A7835BE27', 'Darter, Iowa', 'Etheostoma exile', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 4) 
, ('7DE32283-A227-43A9-8459-FAC2E10A0AB4', 'Bass, Suwannee', 'Micropterus notius', '00000000-0000-0000-0000-000000000000', 0) 
, ('10451251-4939-42E5-B37B-FB206E6077DE', 'Northern snakehead', 'Channa argus', '8B825BD2-0B6A-49BD-BF4D-579D85C1CA68', 5) 
, ('DBBAB8BD-D573-4A12-ACE7-FB22D05EF9F0', 'Sucker, Bridgelip', 'Catostomus columbianus', '3A1100D2-9C12-475B-97ED-92C66269B70A', 0) 
, ('A637D529-EEA6-4082-9175-FB35CBE316CE', 'Springfish, Railroad Valley', 'Crenichthys nevadae', '00000000-0000-0000-0000-000000000000', 0) 
, ('A562C83F-B6A1-4989-AF32-FB46F587C8DE', 'Studfish, Southern', 'Fundulus stellifer', '00000000-0000-0000-0000-000000000000', 0) 
, ('FD6BDC52-5293-41D6-9100-FB87F5FA9886', 'Darter, Relict', 'Etheostoma chienense', '00000000-0000-0000-0000-000000000000', 0) 
, ('CE4F8A21-4F19-4E41-B301-FB8F043B149E', 'Goby, Freshwater Tubenose', 'Proterorhinus semilunaris', '00000000-0000-0000-0000-000000000000', 0) 
, ('25D2584F-9601-4BFF-BAD3-FC61C31BCA89', 'Darter, Buffalo', 'Etheostoma bison', '00000000-0000-0000-0000-000000000000', 0) 
, ('D3657919-EDDA-4B38-A59F-FC7FBAABD714', 'Logperch, Gulf', 'Percina suttkusi', '00000000-0000-0000-0000-000000000000', 0) 
, ('74ACA97B-1B6A-412F-8A83-FCAB4EBDE816', 'Cisco, Ives Lake', 'Coregonus hubbsi', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 0) 
, ('BC19101E-F81C-4A24-9ED6-FCBCB43669C2', 'Darter, Crystal', 'Crystallaria asprella', '04BA8DAB-9030-4B9E-8536-CAC72314E6B6', 32) 
, ('3AA325D5-1CA0-461F-B2EC-FD295853777E', 'Shiner, Striped', 'Luxilus chrysocephalus', '00000000-0000-0000-0000-000000000000', 0) 
, ('0D4F5B3F-6940-4C8E-863B-FE0E928160B8', 'Dace, Western Blacknose', 'Rhinichthys obtusus', '00000000-0000-0000-0000-000000000000', 0) 
, ('DFB7EB63-9D05-4E7A-B58C-FE510014BAEE', 'Sunfish, Bluegill', 'Lepomis macrochirus', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 0) 
, ('B7AA8335-138D-4065-B524-FE628DA08D14', 'Darter, Fountain', 'Etheostoma fonticola', '00000000-0000-0000-0000-000000000000', 0) 
, ('D07EFE63-BAF4-4DD1-9B1C-FE94C5860185', 'Pike, Northern', 'Esox lucius', 'A48B7674-9C12-4B11-95FE-FC4F1A3B3416', 1) 
, ('E8003BDA-F3CE-415D-834E-FF9B157B2DA1', 'Whitefish, Lake', 'Coregonus clupeaformis', '2177A204-800D-413C-9FE9-0E0E0F9D28D4', 1) 
, ('E8023BDA-F3CE-415D-834E-FF9B157B2DA1', 'Red-bellied piranha', 'Pygocentrus nattereri', '70DC9966-6353-4F41-9194-CE539A38C160', 0) 
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- province default limits:
DECLARE @reglink sysname ='https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf'
INSERT INTO regulations (state, chain, fish_id, regulations_sport, regulations_consr, regulations_sport_text, regulations_link) VALUES
     ('ON', NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e', 1, 1, 'Pacific Salmon - 5', @reglink)
    ,('ON', NULL, 'fcf58413-543e-4ad4-9ae4-6728bb62befe', 1, 1, NULL, @reglink)
    ,('ON', NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed', 5, 5, NULL, @reglink)
    ,('ON', NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae', 5, 5, NULL, @reglink)
    ,('ON', NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d', 12, 12, NULL, @reglink)
    ,('ON', NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e', 30, 30, NULL, @reglink)
    ,('ON', '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e', '073cd69e-d9f4-4377-a746-b6f32cb9e3ba', 30, 30, NULL, @reglink)
    ,('ON', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e', 3, 3, NULL, @reglink)
    ,('ON', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1', 3, 3, NULL, @reglink)
    ,('ON', NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e', 6, 6, NULL, @reglink)
    ,('ON', '2038693f-d38c-43c8-b0ce-4e96b0f9af7e', 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97', 6, 6, NULL, @reglink)
    ,('ON', NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8', 1, 1, NULL, @reglink)
    ,('ON', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185', 6, 6, NULL, @reglink)
    ,('ON', NULL, 'b3a33573-8bc6-4803-b977-10f673aad711', 5, 5, NULL, @reglink)
    ,('ON', NULL, '19c45110-154d-477f-ba55-309be16e54ca', 5, 5, NULL, @reglink)
    ,('ON', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c', 6, 6, NULL, @reglink)
    ,('ON', '2cffb500-3e59-4120-9460-055856e9ac5c', '8014674d-ca30-4e61-8fa2-4d80d94e5f45', 6, 6, NULL, @reglink)
    ,('ON', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4', 6, 6, NULL, @reglink)
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Bowfin
EXEC sp_add_regulation 'ON', 10, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 13, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 14, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 19, 'Method: Bow and arrow during daylight hours only', 'May 1', 'July 31', NULL, NULL, NULL, 'D1814745-D6C3-4A95-8503-3C6DFB5B8B21'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- common carp
EXEC sp_add_regulation 'ON', 5, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 6, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 9, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 10, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 12, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 13, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 14, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 15, 'Except Algonquin Park', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 16, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 18, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 19, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 20, '', 'May 1', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 17, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'Second Saturday in May', 'July 31', NULL, NULL, NULL, '4f023204-cdaf-4fae-bf7f-e9319794e8ff'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 1, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 2, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 3, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 4, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 5, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 6, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 7, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 8, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 10, 'Method: Dip net day or night', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 11, 'Method: Dip net day or night. Contact local district office for details', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
EXEC sp_add_regulation 'ON', 15, 'Method: Dip net day or night. Contact local district office for details', 'October 1', 'December 15', NULL, NULL, NULL, '76e514c4-01c3-4a57-8578-035a8cef63ad'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
--   White Sucker
EXEC sp_add_regulation 'ON', 1, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 2, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 3, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 4, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 5, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 6, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 7, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 8, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 9, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 10, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 11, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 12, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 13, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 14, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 15, 'Method: Bow and arrow, spear, and dip net during daylight hours only. Except Algonquin Park', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 16, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 17, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'second Saturday in May', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 18, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 19, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
EXEC sp_add_regulation 'ON', 20, 'Method: Bow and arrow, spear, and dip net during daylight hours only', 'March 1', 'May 31', NULL, NULL, NULL, '32975f54-4568-40ec-b2ae-a5dbc4088927'
    , NULL, 'https://files.ontario.ca/on-con-188/ONCON-188_MNRF_CR_ontario-fishing-regulations-summary-v2.pdf', 2019
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Zone 1
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '073cd69e-d9f4-4377-a746-b6f32cb9e3ba'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', '5, not more than 1 greater than 40 cm', '2, not more than 1 greater than 40', NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'May 1', 'June 30', 0, 0, NULL, 'c0fe652f-cfa2-4148-94c1-24fc2d7140eb'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '1, any size', '3, any size', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '12, any size', '6, any size', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8'        -- Muskellunge
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '6, not more than 2 greater than 61 cm, of which not more than 1 is greater than 86 cm'
    , '2, not more than 1 greater than 61 cm, none greater than 86 cm', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'b3a33573-8bc6-4803-b977-10f673aad711'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, '19c45110-154d-477f-ba55-309be16e54ca'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', 'January 1', 'December 31', NULL, NULL, NULL, 'dfb7eb63-9d05-4e7a-b58c-fe510014baee'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '8014674d-ca30-4e61-8fa2-4d80d94e5f45'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
EXEC sp_add_regulation 'ON', 1, '', NULL, NULL, '50, any size', '25, any size', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-1', 2019, 0
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Zone 2
------------------------------------------------------------------------------------------------------------------------------------------------------------
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'a35109a0-63ba-4bf5-8a25-2e7e39b74f6e'        --- Atlantic Salmon
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '5ab8a0ee-a5ca-43e6-b628-73e2bc12266e'        -- Black & White Crappie
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '073cd69e-d9f4-4377-a746-b6f32cb9e3ba'        -- Black & White Crappie
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'Day after Labour Day', 'December 31', '5, not more than 1 greater than 30 cm', '2, not more than 1 greater than 40'       -- Brook Trout
    , NULL, 'f124f917-d11f-4ed9-9b59-863d184cbfed', NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '5, any size', '2, any size', NULL, '6dbf1306-dc10-421a-a29b-b260d540a0ae'       -- Brown Trout
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '969c00e3-1ed1-4845-bffc-a1dc51e2105d'         -- Channel Catfish
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'May 1', 'June 30', 0, 0, NULL, 'c0fe652f-cfa2-4148-94c1-24fc2d7140eb'                       --  Lake Sturgeon
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'October 1', 'December 31', '2, not more than 1 greater than 56 cm from September 1 to September 30 any size from January 1 to August 31'
    , '1, any size', NULL, 'f3c65c73-f913-43b8-9f22-965ab095d13e'                                                                -- Lake Trout
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '12, any size', '6, any size', NULL, 'e8003bda-f3ce-415d-834e-ff9b157b2da1'      -- Lake Whitefish
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '2, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 4, no size limit from July 1 to November 30'
    , '1, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 2, no size limit from July 1 to November 30'
    , NULL, '2038693f-d38c-43c8-b0ce-4e96b0f9af7e'                                                                              -- Largemouth  Bass
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '2, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 4, no size limit from July 1 to November 30'
    , '1, must be less than 35 cm from January 1 to June 30 and December 1 to December 31 2, no size limit from July 1 to November 30'
    , NULL, 'a85ebf22-4ab9-4a91-a14a-cef6c8e64d97'                                                                              -- Smallmouth Bass
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0

EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'The Friday before the 3rd Saturday in June', '1, must be greater than 91 cm', 0, NULL, '896837e4-3fe3-44c6-baee-5a490fbf64c8'        -- Muskellunge
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '6, not more than 2 greater than 61 cm, of which not more than 1 is greater than 86 cm'
    , '2, not more than 1 greater than 61 cm, none greater than 86 cm', NULL, 'd07efe63-baf4-4dd1-9b1c-fe94c5860185'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'b3a33573-8bc6-4803-b977-10f673aad711'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, '19c45110-154d-477f-ba55-309be16e54ca'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', 'January 1', 'December 31', NULL, NULL, NULL, 'dfb7eb63-9d05-4e7a-b58c-fe510014baee'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '2cffb500-3e59-4120-9460-055856e9ac5c'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '4, not more than 1 greater than 46 cm', '2, not more than 1 greater than 46 cm', NULL, '8014674d-ca30-4e61-8fa2-4d80d94e5f45'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
EXEC sp_add_regulation 'ON', 2, '', NULL, NULL, '50, any size', '25, any size', NULL, '2460a02d-cd68-435f-be2a-0f5aa1275dd4'
    , NULL, 'https://www.ontario.ca/page/sport-fishing-variation-order-fisheries-management-zone-2', 2019, 0
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_enx_merge' AND type = 'P')
    DROP PROCEDURE dbo.sp_enx_merge
GO

/*
 *  refresh actual data

    Usage: 
        EXEC dbo.sp_enx_merge
        select * from global_configuration

*/

CREATE PROCEDURE dbo.sp_enx_merge @dt DATE = '20010101'
WITH EXEC AS CALLER
AS
BEGIN TRY
    SET NOCOUNT ON;

     declare @node int = (select CAST(config_value AS int) from global_configuration WHERE config_attribute = 'node');

     UPDATE global_configuration SET config_value = CAST(getdate()  as sysname) WHERE config_attribute =  'job_executed';

     /* delete data of second level  */

    SELECT @@ROWCOUNT AS result
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
GO
-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.procedures WHERE NAME = 'sp_enx_job' AND type = 'P')
    DROP PROCEDURE dbo.sp_enx_job
GO

CREATE PROCEDURE dbo.sp_enx_job @starttime nvarchar(8), @dbname sysname
WITH EXEC AS CALLER
AS
BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @job sysname = N'ENVX';
    DECLARE @servername nvarchar(28) = @@SERVERNAME
    DECLARE @startdate nvarchar(8) = CONVERT(VARCHAR(10), getdate(), 112)
    DECLARE @ReturnCode INT = 0
    DECLARE @jobId BINARY(16)

    IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = @job)
    BEGIN
        EXEC msdb.dbo.sp_delete_job @job_name = @job;
    END

    EXEC @ReturnCode = msdb.dbo.sp_add_job  @job_name = @job, 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0,     
        @job_id = @jobId OUTPUT

    DECLARE @cmdtemplate sysname = N'EXEC ' + @dbname + N'.dbo.sp_enx_merge'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_enx_merge', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=2, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=@cmdtemplate, 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'ENVX', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20200212, 
		@active_end_date=99991231, 
		@active_start_time=100000, 
		@active_end_time=235959, 
		@schedule_uid=N'363e20f0-a03e-4849-8692-319b0fb84fad'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

    EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'

    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
  
    RETURN @@ROWCOUNT
QuitWithRollback:
    IF NOT EXISTS (SELECT * FROM  msdb.dbo.sysschedules WHERE name = @job)
        RAISERROR ('FAILED: %s Failed to create job %s on %s in %d  ', 16, -1, @job, @servername, @dbname ) 
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER()    AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , ERROR_PROCEDURE() AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
GO
------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------

IF NOT EXISTS (select * from [msdb].[dbo].[sysjobs] WHERE name='sp_enx_job')
BEGIN
    declare @start_time varchar(16) = (select CAST(config_value AS int) from global_configuration WHERE config_attribute = 'job_start')
    declare @dbname sysname = DB_NAME()
    EXEC dbo.sp_enx_job  @start_time, @dbname
END
GO

------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------
