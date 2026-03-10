                         
CREATE TABLE [dbo].[shapeCanada2011](
	[ID] [int] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
	[HYDROUID] [nvarchar](255) NULL,                 -- Uniquely identifies a water feature
	[NAME] [nvarchar](255) NULL,
	[RANK] [bigint] NULL,                            -- [1-7] - Feature rank
	[PRUID] [nvarchar](255) NULL,                    -- Uniquely identifies a province or territory
	[geom] [geography] NULL,
	[typeLake] [int] NULL,             --  1 - lake, 2 - river,  4 - stream (Brook), 8 - pond, 16 - marsh, 32 - backwater, 64 - creek
	  --  128 - canal, 256 - Estuary, 512 - shore, 1024 - drain, 2048 - ocean, 4096 = Wetland, 8192 - Reservoir, 16384 - Dam, 32768 - falls
);

ALTER TABLE [dbo].[shapeCanada2011]  WITH CHECK ADD  CONSTRAINT [enforce_srid_geometry_ghy_000c11a_e] CHECK  (([geom].[STSrid]=(4269)))
GO
ALTER TABLE [dbo].[shapeCanada2011] CHECK CONSTRAINT [enforce_srid_geometry_ghy_000c11a_e]

GO 

------------------------------------------------------------------------------

