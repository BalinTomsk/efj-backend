-------------------------------------------------------------------------------------------------------
if object_id('TR_TXUS003') is not null drop TRIGGER TR_TXUS003
GO
CREATE TRIGGER TR_TXUS003 ON TXUS003 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = [sid], @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
   IF @mli IS NOT NULL AND @stamp IS NOT NULL 
   BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('TR_KSUS005') is not null drop TRIGGER TR_KSUS005
GO
CREATE TRIGGER TR_KSUS005 ON KSUS005 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO        
-------------------------------------------------------------------------------------------------------
if object_id('TR_PAUS007') is not null drop TRIGGER TR_PAUS007
GO
CREATE TRIGGER TR_PAUS007 ON PAUS007 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('TR_WIUS011') is not null drop TRIGGER TR_WIUS011
GO
CREATE TRIGGER TR_WIUS011 ON WIUS011 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('TR_DEUS013') is not null drop TRIGGER TR_DEUS013
GO
CREATE TRIGGER TR_DEUS013 ON DEUS013 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('TR_INUS017') is not null drop TRIGGER TR_INUS017
GO
CREATE TRIGGER TR_INUS017 ON INUS017 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO        
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_ILUS019') is not null 
  drop TRIGGER TR_ILUS019
GO
CREATE TRIGGER TR_ILUS019 ON ILUS019 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO   
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NHUS023') is not null 
  drop TRIGGER TR_NHUS023
GO
CREATE TRIGGER TR_NHUS023 ON NHUS023 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MDUS029') is not null 
  drop TRIGGER TR_MDUS029
GO
CREATE TRIGGER TR_MDUS029 ON MDUS029 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO          
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_DCUS031') is not null 
  drop TRIGGER TR_DCUS031
GO
CREATE TRIGGER TR_DCUS031 ON DCUS031 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO         
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_COUS037') is not null 
  drop TRIGGER TR_COUS037
GO
CREATE TRIGGER TR_COUS037 ON COUS037 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO       
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MIUS041') is not null 
  drop TRIGGER TR_MIUS041
GO
CREATE TRIGGER TR_MIUS041 ON MIUS041 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_VAUS043') is not null 
  drop TRIGGER TR_VAUS043
GO
CREATE TRIGGER TR_VAUS043 ON VAUS043 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MEUS047') is not null 
  drop TRIGGER TR_MEUS047
GO
CREATE TRIGGER TR_MEUS047 ON MEUS047 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO          
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_AKUS053') is not null 
  drop TRIGGER TR_AKUS053
GO
CREATE TRIGGER TR_AKUS053 ON AKUS053 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_SCUS059') is not null 
  drop TRIGGER TR_SCUS059
GO
CREATE TRIGGER TR_SCUS059 ON SCUS059 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO   
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_RIUS061') is not null 
  drop TRIGGER TR_RIUS061
GO
CREATE TRIGGER TR_RIUS061 ON RIUS061 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_WAUS067') is not null 
  drop TRIGGER TR_WAUS067
GO
CREATE TRIGGER TR_WAUS067 ON WAUS067 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MAUS071') is not null 
  drop TRIGGER TR_MAUS071
GO
CREATE TRIGGER TR_MAUS071 ON MAUS071 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MAUS071') is not null 
  drop TRIGGER TR_MAUS071
GO
CREATE TRIGGER TR_MAUS071 ON MAUS071 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NYUS079') is not null 
  drop TRIGGER TR_NYUS079
GO
CREATE TRIGGER TR_NYUS079 ON NYUS079 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_OHUS083') is not null 
  drop TRIGGER TR_OHUS083
GO
CREATE TRIGGER TR_OHUS083 ON OHUS083 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO           
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_SDUS089') is not null 
  drop TRIGGER TR_SDUS089
GO
CREATE TRIGGER TR_SDUS089 ON SDUS089 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO       
------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_CTUS097') is not null 
  drop TRIGGER TR_CTUS097
GO
CREATE TRIGGER TR_CTUS097 ON CTUS097 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO       
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_LAUS101') is not null 
  drop TRIGGER TR_LAUS101
GO
CREATE TRIGGER TR_LAUS101 ON LAUS101 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO         
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NJUS103') is not null 
  drop TRIGGER TR_NJUS103
GO
CREATE TRIGGER TR_NJUS103 ON NJUS103 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MOUS107') is not null 
  drop TRIGGER TR_MOUS107
GO
CREATE TRIGGER TR_MOUS107 ON MOUS107 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_CAUS109') is not null 
  drop TRIGGER TR_CAUS109
GO
CREATE TRIGGER TR_CAUS109 ON CAUS109 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_ORUS113') is not null 
  drop TRIGGER TR_ORUS113
GO
CREATE TRIGGER TR_ORUS113 ON ORUS113 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MNUS127') is not null 
  drop TRIGGER TR_MNUS127
GO
CREATE TRIGGER TR_MNUS127 ON MNUS127 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MTUS131') is not null 
  drop TRIGGER TR_MTUS131
GO
CREATE TRIGGER TR_MTUS131 ON MTUS131 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_OKUS137') is not null 
  drop TRIGGER TR_OKUS137
GO
CREATE TRIGGER TR_OKUS137 ON OKUS137 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_FLUS139') is not null 
  drop TRIGGER TR_FLUS139
GO
CREATE TRIGGER TR_FLUS139 ON FLUS139 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_ARUS149') is not null 
  drop TRIGGER TR_ARUS149
GO
CREATE TRIGGER TR_ARUS149 ON ARUS149 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_IAUS151') is not null 
  drop TRIGGER TR_IAUS151
GO
CREATE TRIGGER TR_IAUS151 ON IAUS151 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO        
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_VTUS157') is not null 
  drop TRIGGER TR_VTUS157
GO
CREATE TRIGGER TR_VTUS157 ON VTUS157 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_ALUS163') is not null 
  drop TRIGGER TR_ALUS163
GO
CREATE TRIGGER TR_ALUS163 ON ALUS163 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NDUS167') is not null 
  drop TRIGGER TR_NDUS167
GO
CREATE TRIGGER TR_NDUS167 ON NDUS167 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_IDUS173') is not null 
  drop TRIGGER TR_IDUS173
GO
CREATE TRIGGER TR_IDUS173 ON IDUS173 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_GAUS179') is not null 
  drop TRIGGER TR_GAUS179
GO
CREATE TRIGGER TR_GAUS179 ON GAUS179 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_AZUS181') is not null 
  drop TRIGGER TR_AZUS181
GO
CREATE TRIGGER TR_AZUS181 ON AZUS181 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_MSUS191') is not null 
  drop TRIGGER TR_MSUS191
GO
CREATE TRIGGER TR_MSUS191 ON MSUS191 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO        
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_TNUS193') is not null 
  drop TRIGGER TR_TNUS193
GO
CREATE TRIGGER TR_TNUS193 ON TNUS193 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NCUS197') is not null 
  drop TRIGGER TR_NCUS197
GO
CREATE TRIGGER TR_NCUS197 ON NCUS197 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NEUS199') is not null 
  drop TRIGGER TR_NEUS199
GO
CREATE TRIGGER TR_NEUS199 ON NEUS199 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_WVUS211') is not null 
  drop TRIGGER TR_WVUS211
GO
CREATE TRIGGER TR_WVUS211 ON WVUS211 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_WYUS223') is not null 
  drop TRIGGER TR_WYUS223
GO
CREATE TRIGGER TR_WYUS223 ON WYUS223 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO      
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_HIUS227') is not null 
  drop TRIGGER TR_HIUS227
GO
CREATE TRIGGER TR_HIUS227 ON HIUS227 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO   
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_NMUS229') is not null 
  drop TRIGGER TR_NMUS229
GO
CREATE TRIGGER TR_NMUS229 ON NMUS229 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO    
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_UTUS233') is not null 
  drop TRIGGER TR_UTUS233
GO
CREATE TRIGGER TR_UTUS233 ON UTUS233 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO     
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_KYUS239') is not null 
  drop TRIGGER TR_KYUS239
GO
CREATE TRIGGER TR_KYUS239 ON KYUS239 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO          
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_PRUS241') is not null 
  drop TRIGGER TR_PRUS241
GO
CREATE TRIGGER TR_PRUS241 ON PRUS241 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO         
-------------------------------------------------------------------------------------------------------
if object_id('dbo.TR_VIUS251') is not null 
  drop TRIGGER TR_VIUS251
GO
CREATE TRIGGER TR_VIUS251 ON VIUS251 
FOR INSERT 
NOT FOR REPLICATION
AS 
SET NOCOUNT ON
BEGIN
    DECLARE @stamp datetime, @mli varchar(64), @sid bigint
    DECLARE @elevation float, @temperature float  , @conductance float, @turbidity float, @oxygen float, @ph float, @discharge float  

    SELECT @stamp = stamp, @elevation = elevation, @mli = mli, @sid = sid, @temperature = temperature
    , @conductance = conductance, @ph = ph, @turbidity = turbidity, @oxygen = oxygen, @discharge = discharge FROM INSERTED
    IF @mli IS NOT NULL AND @stamp IS NOT NULL 
    BEGIN
		UPDATE WaterStation SET updData = CASE WHEN updData IS NOT NULL AND @stamp > updData 
			 THEN @stamp ELSE ISNULL(updData, @stamp) END
		  WHERE mli=@mli   
		EXEC ENVionX.dbo.spUpdateCurrentWaterState @mli, @stamp, @elevation, @sid, @temperature, @conductance, @ph
		                                               , @turbidity, @oxygen, @discharge
	END
END
GO   
