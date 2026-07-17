SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for the per-water-body fish "status" flag (lake_fish.status bitmask):
    bit 0 (value 1) = At Risk   -> shown in RED   on the river view + EditLakeFish list
    bit 1 (value 2) = Invasive  -> shown in ORANGE on the river view + EditLakeFish list

  Callers:
    - dbo.spAddFish (FishTracker.Editor.EditLakeFish.btSaveFish_Click) writes @status.
    - dbo.fn_lake_fish (EditLakeFish.LoadPage) exposes status in its XML.
    - dbo.fn_EditLakeFish (Resources.wfRiverViewer.LoadFish) returns status in its table.

  TEST 1 - spAddFish stores the status bitmask on lake_fish
  TEST 2 - fn_lake_fish emits the status attribute in its XML
  TEST 3 - fn_EditLakeFish returns the status column
*/
PRINT 'Unit tests for lake_fish.status (At Risk / Invasive)';
GO
-- ============================================================================
-- TEST 1: spAddFish stores the status bitmask on lake_fish
-- ============================================================================
BEGIN TRAN LFS_Test1
    declare @test_name sysname = N'LFS_Test1 [spAddFish] : stores status bitmask'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status1 tinyint;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test
DECLARE @Lake1     uniqueidentifier = NEWID();
DECLARE @Family1   uniqueidentifier = NEWID();
DECLARE @Fish1     uniqueidentifier = NEWID();
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake1, 1, N'ut-lake-lfs1');
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created) VALUES (@Family1, N'ut-family-lfs1', 900101, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@Fish1, N'Carp-lfs1', N'Cyprinus ut-lfs1', @Family1, SYSUTCDATETIME(), SYSUTCDATETIME());
DECLARE @Sid1 int = (SELECT sid FROM dbo.fish WHERE fish_id = @Fish1);

-- 2. execute unit test : at risk (1) + invasive (2) = 3
EXEC dbo.spAddFish @Lake1, @Sid1, N'http://ut/lfs1', 0, 3, N'';
SELECT @Status1 = status FROM dbo.lake_fish WHERE lake_id = @Lake1 AND fish_id = @Fish1;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification
IF @Status1 IS NULL OR @Status1 <> 3
   RAISERROR ('TEST 1 FAIL [%dms]: expected lake_fish.status = 3', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: spAddFish stored the status bitmask (3)'

ROLLBACK TRAN LFS_Test1
GO
-- ============================================================================
-- TEST 2: fn_lake_fish emits the status attribute in its XML
-- ============================================================================
BEGIN TRAN LFS_Test2
    declare @test_name sysname = N'LFS_Test2 [fn_lake_fish] : emits status attribute'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @XmlStatus int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test
DECLARE @Lake2     uniqueidentifier = NEWID();
DECLARE @Family2   uniqueidentifier = NEWID();
DECLARE @Fish2     uniqueidentifier = NEWID();
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake2, 1, N'ut-lake-lfs2');
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created) VALUES (@Family2, N'ut-family-lfs2', 900102, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@Fish2, N'Pike-lfs2', N'Esox ut-lfs2', @Family2, SYSUTCDATETIME(), SYSUTCDATETIME());
INSERT INTO dbo.fish_zoo (fish_id) VALUES (@Fish2);
INSERT INTO dbo.lake_fish (lake_Id, fish_Id, created, link, status, sid, lake_fish_id)
VALUES (@Lake2, @Fish2, SYSUTCDATETIME(), N'http://ut/lfs2', 2, 900202, NEWID());

-- 2. execute unit test
DECLARE @Doc2 xml = dbo.fn_lake_fish(@Lake2);
SELECT @XmlStatus = @Doc2.value('(//fish/@status)[1]', 'int');

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification
IF @XmlStatus IS NULL OR @XmlStatus <> 2
   RAISERROR ('TEST 2 FAIL [%dms]: expected fish/@status = 2 in fn_lake_fish XML', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_fish emitted status=2'

ROLLBACK TRAN LFS_Test2
GO
-- ============================================================================
-- TEST 3: fn_EditLakeFish returns the status column
-- ============================================================================
BEGIN TRAN LFS_Test3
    declare @test_name sysname = N'LFS_Test3 [fn_EditLakeFish] : returns status column'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @EditStatus int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test
DECLARE @Lake3     uniqueidentifier = NEWID();
DECLARE @Family3   uniqueidentifier = NEWID();
DECLARE @Fish3     uniqueidentifier = NEWID();
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake3, 1, N'ut-lake-lfs3');
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created) VALUES (@Family3, N'ut-family-lfs3', 900103, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@Fish3, N'Bass-lfs3', N'Micropterus ut-lfs3', @Family3, SYSUTCDATETIME(), SYSUTCDATETIME());
INSERT INTO dbo.fish_zoo (fish_id) VALUES (@Fish3);
INSERT INTO dbo.lake_fish (lake_Id, fish_Id, created, link, status, sid, lake_fish_id)
VALUES (@Lake3, @Fish3, SYSUTCDATETIME(), N'http://ut/lfs3', 1, 900203, NEWID());

-- 2. execute unit test
SELECT @EditStatus = status FROM dbo.fn_EditLakeFish(@Lake3) WHERE fish_id = @Fish3;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification
IF @EditStatus IS NULL OR @EditStatus <> 1
   RAISERROR ('TEST 3 FAIL [%dms]: expected fn_EditLakeFish status = 1', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_EditLakeFish returned status=1'

ROLLBACK TRAN LFS_Test3
GO
