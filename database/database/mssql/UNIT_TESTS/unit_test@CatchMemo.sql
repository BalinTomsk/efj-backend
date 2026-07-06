SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for the Catch Log (catch memo) feature: dbo.catch_memo, dbo.catch_memo_photo,
  dbo.catch_pending_fish, dbo.sp_add_catch_memo, dbo.fn_catch_memo_list, dbo.fn_catch_memo_get,
  dbo.sp_add_catch_pending_fish, dbo.sp_set_catch_pending_fish_status, dbo.fn_lake_fish_list,
  dbo.fn_catch_weather_snapshot, dbo.sp_add_catch_memo_photo, dbo.sp_del_catch_memo_photo,
  dbo.fn_catch_memo_photo_list, dbo.sp_NewGuidV7, dbo.sp_clone_catch_memo,
  dbo.fn_catch_memo_pending_clone_id.

  Uses real tables (catch_memo / catch_pending_fish have no FKs, so no parent setup is
  needed for them; lake_fish needs a real fish + fish_family row as fixtures for the
  pending-fish dedup tests; the weather tests need a real dbo.Lake + dbo.WaterStation +
  dbo.weather_Forecast + dbo.CurrentWaterState row). Each test is its own named transaction,
  rolled back at the end of its own batch - database state restored, and one test's failure
  cannot affect another's fixtures.

  TEST  1 - sp_add_catch_memo insert stores weight/length/units/released/private
  TEST  2 - sp_add_catch_memo upsert (same @id) updates the stored values
  TEST  3 - fn_catch_memo_list hides a private memo from a guest and from another user
  TEST  4 - fn_catch_memo_list shows a private memo to its author and to an admin
  TEST  5 - fn_catch_memo_get returns weight/length/released/private for one memo
  TEST  6 - non-author update is blocked (author/lock guard unaffected by new columns)
  TEST  7 - sp_add_catch_pending_fish queues a new (unlisted) species suggestion
  TEST  8 - sp_add_catch_pending_fish is a no-op for a species already on the lake
  TEST  9 - sp_add_catch_pending_fish dedups a repeat suggestion (no duplicate queue row)
  TEST 10 - sp_set_catch_pending_fish_status marks a suggestion approved
  TEST 11 - fn_lake_fish_list returns the species assigned to a water body
  TEST 12 - fn_catch_weather_snapshot returns the forecast row (air + water temp) for a
            lake's station + date
  TEST 13 - fn_catch_weather_snapshot returns no row for a lake with no weather station
  TEST 14 - sp_add_catch_memo stores the weather + water temp snapshot and
            fn_catch_memo_list surfaces it
  TEST 15 - fn_catch_memo_list flags the max-weight catch as personal best (unit-normalized)
  TEST 16 - fn_catch_memo_list never flags a personal best when the catch has no fish_id
  TEST 17 - fn_catch_weather_snapshot never attaches today's water temp to an old catch date
  TEST 18 - sp_add_catch_memo_photo stores description/author and fn_catch_memo_photo_list
            returns them
  TEST 19 - sp_del_catch_memo_photo by a non-admin only hides the photo (row kept, excluded
            from the listing)
  TEST 20 - sp_del_catch_memo_photo by an admin physically deletes the row
  TEST 21 - sp_add_catch_memo_photo caps a memo at 3 non-hidden photos
  TEST 22 - sp_NewGuidV7 returns distinct, correctly-versioned ids that sort in generation order
            (catch_memo_photo_id / catch_pending_fish_id are generated this way, replacing the
            INT IDENTITY those columns used to be -- see the "Important" note in
            database/CLAUDE.md on why an IDENTITY counter is unsafe under peer-to-peer replication)
  TEST 23 - sp_clone_catch_memo copies most fields but never species/weight/length/photos
  TEST 24 - sp_clone_catch_memo refuses a second clone while the first is unfinished
  TEST 25 - cloning is allowed again once the pending clone gets a species + photo
  TEST 26 - sp_clone_catch_memo refuses a private memo for a non-owner, allows owner/admin
  TEST 27 - fn_catch_memo_list hides an incomplete public memo (no catch date AND no visible
            photo) from a guest and another user, but still shows it to the author and an admin
  TEST 28 - fn_catch_memo_list shows a public memo to everyone once it has a catch date OR a
            non-hidden photo; a public memo whose only photo is hidden and has no date stays hidden
*/

-- ============================================================================
-- TEST 1: sp_add_catch_memo insert stores weight/length/units/released/private
-- ============================================================================
BEGIN TRAN CM_Test01
    declare @test_name sysname = N'CM_Test01 [sp_add_catch_memo] : insert stores weight/length/units/released/private'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @W float, @WU nvarchar(8), @L float, @LU nvarchar(8), @Rel bit, @Priv bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake1   uniqueidentifier = NEWID();
DECLARE @Author1 uniqueidentifier = NEWID();
DECLARE @Memo1   uniqueidentifier = NEWID();

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo @id=@Memo1, @lake_id=@Lake1, @userid=@Author1,
    @species=N'Northern Pike', @text=N'nice one', @catch_date='2026-06-29',
    @weight=3.2, @weight_unit=N'kg', @length=65, @length_unit=N'cm',
    @released=1, @private=1;
SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
       @LU=catch_memo_length_unit, @Rel=catch_memo_released, @Priv=catch_memo_private
FROM dbo.catch_memo WHERE catch_memo_id = @Memo1;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @W IS NULL OR @W <> 3.2 OR @WU <> N'kg' OR @L <> 65 OR @LU <> N'cm' OR @Rel <> 1 OR @Priv <> 1
   RAISERROR ('TEST 1 FAIL [%dms]: unexpected stored values', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stored weight/length/units/released/private'

ROLLBACK TRAN CM_Test01
GO

-- ============================================================================
-- TEST 2: sp_add_catch_memo upsert (same @id) updates the stored values
-- ============================================================================
BEGIN TRAN CM_Test02
    declare @test_name sysname = N'CM_Test02 [sp_add_catch_memo] : upsert updates weight/unit/length/released/private'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @W float, @WU nvarchar(8), @L float, @Rel bit, @Priv bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake2   uniqueidentifier = NEWID();
DECLARE @Author2 uniqueidentifier = NEWID();
DECLARE @Memo2   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo2, @lake_id=@Lake2, @userid=@Author2,
    @species=N'Northern Pike', @text=N'nice one', @catch_date='2026-06-29',
    @weight=3.2, @weight_unit=N'kg', @length=65, @length_unit=N'cm',
    @released=1, @private=1;

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo @id=@Memo2, @lake_id=@Lake2, @userid=@Author2,
    @species=N'Northern Pike', @text=N'nice one', @catch_date='2026-06-29',
    @weight=7, @weight_unit=N'lb', @length=null, @length_unit=null,
    @released=null, @private=0;
SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
       @Rel=catch_memo_released, @Priv=catch_memo_private
FROM dbo.catch_memo WHERE catch_memo_id = @Memo2;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @W IS NULL OR @W <> 7 OR @WU <> N'lb' OR @L IS NOT NULL OR @Rel IS NOT NULL OR @Priv <> 0
   RAISERROR ('TEST 2 FAIL [%dms]: upsert did not update as expected', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: upsert updated weight/unit/length/released/private'

ROLLBACK TRAN CM_Test02
GO

-- ============================================================================
-- TEST 3: fn_catch_memo_list hides a private memo from a guest / another user
-- ============================================================================
BEGIN TRAN CM_Test03
    declare @test_name sysname = N'CM_Test03 [fn_catch_memo_list] : private memo hidden from guest and other user'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @GuestCnt int, @OtherCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake3      uniqueidentifier = NEWID();
DECLARE @Author3    uniqueidentifier = NEWID();
DECLARE @OtherUser3 uniqueidentifier = NEWID();
DECLARE @Memo3      uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo3, @lake_id=@Lake3, @userid=@Author3,
    @species=N'Northern Pike', @catch_date='2026-06-29', @private=1;

-- 2. execute unit test

SELECT @GuestCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake3, NULL, 0) WHERE catch_memo_id = @Memo3;
SELECT @OtherCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake3, @OtherUser3, 0) WHERE catch_memo_id = @Memo3;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @GuestCnt IS NULL OR @GuestCnt <> 0 OR @OtherCnt IS NULL OR @OtherCnt <> 0
   RAISERROR ('TEST 3 FAIL [%dms]: guest/other user could see the private memo', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: private memo hidden from guest and other user'

ROLLBACK TRAN CM_Test03
GO

-- ============================================================================
-- TEST 4: fn_catch_memo_list shows a private memo to author and admin
-- ============================================================================
BEGIN TRAN CM_Test04
    declare @test_name sysname = N'CM_Test04 [fn_catch_memo_list] : private memo visible to author and admin'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @AuthorCnt int, @AdminCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake4   uniqueidentifier = NEWID();
DECLARE @Author4 uniqueidentifier = NEWID();
DECLARE @Admin4  uniqueidentifier = NEWID();
DECLARE @Memo4   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo4, @lake_id=@Lake4, @userid=@Author4,
    @species=N'Northern Pike', @catch_date='2026-06-29', @private=1;

-- 2. execute unit test

SELECT @AuthorCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake4, @Author4, 0) WHERE catch_memo_id = @Memo4;
SELECT @AdminCnt  = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake4, @Admin4, 1)  WHERE catch_memo_id = @Memo4;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @AuthorCnt IS NULL OR @AuthorCnt <> 1 OR @AdminCnt IS NULL OR @AdminCnt <> 1
   RAISERROR ('TEST 4 FAIL [%dms]: private memo not visible to author/admin', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: private memo visible to author and admin'

ROLLBACK TRAN CM_Test04
GO

-- ============================================================================
-- TEST 5: fn_catch_memo_get returns weight/length/released/private
-- ============================================================================
BEGIN TRAN CM_Test05
    declare @test_name sysname = N'CM_Test05 [fn_catch_memo_get] : returns weight/length/released/private for one memo'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @W float, @WU nvarchar(8), @L float, @LU nvarchar(8), @Rel bit, @Priv bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake5   uniqueidentifier = NEWID();
DECLARE @Author5 uniqueidentifier = NEWID();
DECLARE @Memo5   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo5, @lake_id=@Lake5, @userid=@Author5,
    @species=N'Northern Pike', @catch_date='2026-06-29',
    @weight=3.2, @weight_unit=N'kg', @length=65, @length_unit=N'cm',
    @released=1, @private=1;

-- 2. execute unit test

SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
       @LU=catch_memo_length_unit, @Rel=catch_memo_released, @Priv=catch_memo_private
FROM dbo.fn_catch_memo_get(@Memo5, @Author5, 0);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @W IS NULL OR @W <> 3.2 OR @WU <> N'kg' OR @L <> 65 OR @LU <> N'cm' OR @Rel <> 1 OR @Priv <> 1
   RAISERROR ('TEST 5 FAIL [%dms]: fn_catch_memo_get returned unexpected values', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_catch_memo_get returned correct new-column values'

ROLLBACK TRAN CM_Test05
GO

-- ============================================================================
-- TEST 6: non-author update is blocked (author/lock guard still enforced)
-- ============================================================================
BEGIN TRAN CM_Test06
    declare @test_name sysname = N'CM_Test06 [sp_add_catch_memo] : non-author update is blocked'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @W float, @Priv bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake6      uniqueidentifier = NEWID();
DECLARE @Author6    uniqueidentifier = NEWID();
DECLARE @OtherUser6 uniqueidentifier = NEWID();
DECLARE @Memo6      uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo6, @lake_id=@Lake6, @userid=@Author6,
    @species=N'Northern Pike', @catch_date='2026-06-29', @weight=3.2, @private=1;

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo @id=@Memo6, @lake_id=@Lake6, @userid=@OtherUser6,
    @weight=999, @private=0, @is_admin=0;
SELECT @W=catch_memo_weight, @Priv=catch_memo_private FROM dbo.catch_memo WHERE catch_memo_id = @Memo6;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @W IS NULL OR @W <> 3.2 OR @Priv <> 1
   RAISERROR ('TEST 6 FAIL [%dms]: non-author update was NOT blocked', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: non-author update was blocked (values unchanged)'

ROLLBACK TRAN CM_Test06
GO

-- ============================================================================
-- TEST 7: sp_add_catch_pending_fish queues a new (unlisted) species suggestion
-- ============================================================================
BEGIN TRAN CM_Test07
    declare @test_name sysname = N'CM_Test07 [sp_add_catch_pending_fish] : queues a new species suggestion'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @PendCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake7   uniqueidentifier = NEWID();
DECLARE @Author7 uniqueidentifier = NEWID();

-- 2. execute unit test

EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake7, @userid=@Author7, @fish_name=N'Muskellunge-ut';
SELECT @PendCnt = COUNT(*) FROM dbo.catch_pending_fish
WHERE catch_pending_fish_lake_id = @Lake7 AND catch_pending_fish_name = N'Muskellunge-ut';

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @PendCnt IS NULL OR @PendCnt <> 1
   RAISERROR ('TEST 7 FAIL [%dms]: expected 1 queued row', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: new species queued in catch_pending_fish'

ROLLBACK TRAN CM_Test07
GO

-- ============================================================================
-- TEST 8: sp_add_catch_pending_fish is a no-op for a species already on the lake
-- ============================================================================
BEGIN TRAN CM_Test08
    declare @test_name sysname = N'CM_Test08 [sp_add_catch_pending_fish] : no-op for a species already on the lake'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @KnownCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake8     uniqueidentifier = NEWID();
DECLARE @Author8   uniqueidentifier = NEWID();
DECLARE @FamilyId8 uniqueidentifier = NEWID();
DECLARE @FishId8   uniqueidentifier = NEWID();
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
VALUES (@FamilyId8, N'ut-family-8', 900008, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@FishId8, N'Walleye-ut8', N'Sander ut-vitreus-8', @FamilyId8, SYSUTCDATETIME(), SYSUTCDATETIME());
INSERT INTO dbo.lake_fish (lake_Id, fish_Id, created, lake_fish_id)
VALUES (@Lake8, @FishId8, SYSUTCDATETIME(), NEWID());

-- 2. execute unit test

EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake8, @userid=@Author8, @fish_name=N'Walleye-ut8';
SELECT @KnownCnt = COUNT(*) FROM dbo.catch_pending_fish
WHERE catch_pending_fish_lake_id = @Lake8 AND catch_pending_fish_name = N'Walleye-ut8';

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @KnownCnt IS NULL OR @KnownCnt <> 0
   RAISERROR ('TEST 8 FAIL [%dms]: expected 0 queued rows for an already-known species', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: already-known species was not queued'

ROLLBACK TRAN CM_Test08
GO

-- ============================================================================
-- TEST 9: sp_add_catch_pending_fish dedups a repeat suggestion
-- ============================================================================
BEGIN TRAN CM_Test09
    declare @test_name sysname = N'CM_Test09 [sp_add_catch_pending_fish] : dedups a repeat suggestion'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @DupPendCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake9      uniqueidentifier = NEWID();
DECLARE @Author9    uniqueidentifier = NEWID();
DECLARE @OtherUser9 uniqueidentifier = NEWID();

-- 2. execute unit test

EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake9, @userid=@Author9, @fish_name=N'Muskellunge-ut9';
EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake9, @userid=@OtherUser9, @fish_name=N'Muskellunge-ut9';
SELECT @DupPendCnt = COUNT(*) FROM dbo.catch_pending_fish
WHERE catch_pending_fish_lake_id = @Lake9 AND catch_pending_fish_name = N'Muskellunge-ut9';

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @DupPendCnt IS NULL OR @DupPendCnt <> 1
   RAISERROR ('TEST 9 FAIL [%dms]: repeat suggestion duplicated the queue row', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: repeat suggestion did not duplicate the queue row'

ROLLBACK TRAN CM_Test09
GO

-- ============================================================================
-- TEST 10: sp_set_catch_pending_fish_status marks a suggestion approved
-- ============================================================================
BEGIN TRAN CM_Test10
    declare @test_name sysname = N'CM_Test10 [sp_set_catch_pending_fish_status] : marks a suggestion approved'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status tinyint, @DecidedBy uniqueidentifier, @Admin10 uniqueidentifier;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake10   uniqueidentifier = NEWID();
DECLARE @Author10 uniqueidentifier = NEWID();
SET @Admin10 = NEWID();
EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake10, @userid=@Author10, @fish_name=N'Muskellunge-ut10';
DECLARE @PendId uniqueidentifier;
SELECT @PendId = catch_pending_fish_id FROM dbo.catch_pending_fish
WHERE catch_pending_fish_lake_id = @Lake10 AND catch_pending_fish_name = N'Muskellunge-ut10';

-- 2. execute unit test

EXEC dbo.sp_set_catch_pending_fish_status @id=@PendId, @status=1, @admin_userid=@Admin10;
SELECT @Status=catch_pending_fish_status, @DecidedBy=catch_pending_fish_decided_by
FROM dbo.catch_pending_fish WHERE catch_pending_fish_id = @PendId;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Status IS NULL OR @Status <> 1 OR @DecidedBy IS NULL OR @DecidedBy <> @Admin10
   RAISERROR ('TEST 10 FAIL [%dms]: status/decided_by not as expected', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: suggestion marked approved by admin'

ROLLBACK TRAN CM_Test10
GO

-- ============================================================================
-- TEST 11: fn_lake_fish_list returns the species assigned to the water body
-- ============================================================================
BEGIN TRAN CM_Test11
    declare @test_name sysname = N'CM_Test11 [fn_lake_fish_list] : returns the species assigned to a water body'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @LakeFishCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake11     uniqueidentifier = NEWID();
DECLARE @FamilyId11 uniqueidentifier = NEWID();
DECLARE @FishId11   uniqueidentifier = NEWID();
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
VALUES (@FamilyId11, N'ut-family-11', 900011, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@FishId11, N'Walleye-ut11', N'Sander ut-vitreus-11', @FamilyId11, SYSUTCDATETIME(), SYSUTCDATETIME());
INSERT INTO dbo.lake_fish (lake_Id, fish_Id, created, lake_fish_id)
VALUES (@Lake11, @FishId11, SYSUTCDATETIME(), NEWID());

-- 2. execute unit test

SELECT @LakeFishCnt = COUNT(*) FROM dbo.fn_lake_fish_list(@Lake11) WHERE fish_id = @FishId11 AND fish_name = N'Walleye-ut11';

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @LakeFishCnt IS NULL OR @LakeFishCnt <> 1
   RAISERROR ('TEST 11 FAIL [%dms]: expected 1 row from fn_lake_fish_list', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_fish_list returned the assigned species'

ROLLBACK TRAN CM_Test11
GO

-- ============================================================================
-- TEST 12: fn_catch_weather_snapshot returns the forecast row for a lake's station + date
-- ============================================================================
BEGIN TRAN CM_Test12
    declare @test_name sysname = N'CM_Test12 [fn_catch_weather_snapshot] : returns the forecast row for a lake''s station + date'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @WTemp float, @WPress float, @WText nvarchar(64), @WIcon nvarchar(255), @WaterTemp float;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake12    uniqueidentifier = NEWID();
DECLARE @Station12 uniqueidentifier = NEWID();
DECLARE @Mli12     varchar(64) = 'UT_MLI_012';
DECLARE @Today12   date = CAST(GETDATE() AS DATE);   -- dynamic: CurrentWaterState is only joined for today/yesterday
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake12, 1, N'UT Lake 12');
INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid, lakeId)
VALUES (@Station12, @Mli12, N'UT Lake 12', 1, N'UT Station 12', N'UT Desc', N'UT County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 900012, @Lake12);
INSERT INTO dbo.weather_Forecast (link, tmHigh, tmLow, gpfDay, gpfNight, dt, mli, pressure, shortText, icon)
VALUES (@Station12, 18.0, 10.0, 0, 0, @Today12, @Mli12, 1013, N'Partly Cloudy', N'02d');
INSERT INTO dbo.CurrentWaterState (mli, stamp, temperature, sid, iterstamp)
VALUES (@Mli12, GETUTCDATE(), 14.5, 900012, GETUTCDATE());

-- 2. execute unit test

SELECT @WTemp=weather_temp, @WPress=weather_pressure, @WText=weather_text, @WIcon=weather_icon, @WaterTemp=water_temp
FROM dbo.fn_catch_weather_snapshot(@Lake12, @Today12);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @WTemp IS NULL OR @WTemp <> 18.0 OR @WPress <> 1013 OR @WText <> N'Partly Cloudy' OR @WIcon <> N'02d' OR @WaterTemp IS NULL OR @WaterTemp <> 14.5
   RAISERROR ('TEST 12 FAIL [%dms]: unexpected snapshot values', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_catch_weather_snapshot returned the forecast row'

ROLLBACK TRAN CM_Test12
GO

-- ============================================================================
-- TEST 13: fn_catch_weather_snapshot returns no row for a lake with no weather station
-- ============================================================================
BEGIN TRAN CM_Test13
    declare @test_name sysname = N'CM_Test13 [fn_catch_weather_snapshot] : returns no row for a lake with no weather station'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @NoSnapCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake13 uniqueidentifier = NEWID();
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake13, 1, N'UT Lake 13');

-- 2. execute unit test

SELECT @NoSnapCnt = COUNT(*) FROM dbo.fn_catch_weather_snapshot(@Lake13, '2026-06-29');

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @NoSnapCnt IS NULL OR @NoSnapCnt <> 0
   RAISERROR ('TEST 13 FAIL [%dms]: expected 0 rows for a lake with no weather station', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake with no weather station returned no row'

ROLLBACK TRAN CM_Test13
GO

-- ============================================================================
-- TEST 14: sp_add_catch_memo stores the weather snapshot and fn_catch_memo_list surfaces it
-- ============================================================================
BEGIN TRAN CM_Test14
    declare @test_name sysname = N'CM_Test14 [sp_add_catch_memo] : weather snapshot stored and returned by fn_catch_memo_list'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @WTemp float, @WPress float, @WText nvarchar(64), @WIcon nvarchar(255), @WaterTemp float;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake14   uniqueidentifier = NEWID();
DECLARE @Author14 uniqueidentifier = NEWID();
DECLARE @Memo14   uniqueidentifier = NEWID();
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake14, 1, N'UT Lake 14');

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo @id=@Memo14, @lake_id=@Lake14, @userid=@Author14,
    @species=N'Northern Pike', @catch_date='2026-06-29',
    @weather_temp=18.0, @weather_pressure=1013, @weather_text=N'Partly Cloudy', @weather_icon=N'02d', @water_temp=14.5;
SELECT @WTemp=catch_memo_weather_temp, @WPress=catch_memo_weather_pressure,
       @WText=catch_memo_weather_text, @WIcon=catch_memo_weather_icon, @WaterTemp=catch_memo_water_temp
FROM dbo.fn_catch_memo_list(@Lake14, @Author14, 0) WHERE catch_memo_id = @Memo14;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @WTemp IS NULL OR @WTemp <> 18.0 OR @WPress <> 1013 OR @WText <> N'Partly Cloudy' OR @WIcon <> N'02d' OR @WaterTemp IS NULL OR @WaterTemp <> 14.5
   RAISERROR ('TEST 14 FAIL [%dms]: unexpected weather columns on the memo', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: weather snapshot stored and returned by fn_catch_memo_list'

ROLLBACK TRAN CM_Test14
GO

-- ============================================================================
-- TEST 15: fn_catch_memo_list flags the max-weight catch as personal best (unit-normalized)
-- ============================================================================
BEGIN TRAN CM_Test15
    declare @test_name sysname = N'CM_Test15 [fn_catch_memo_list] : flags the max-weight catch as personal best'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @SmallPb bit, @BigPb bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake15      uniqueidentifier = NEWID();
DECLARE @Author15    uniqueidentifier = NEWID();
DECLARE @FamilyId15  uniqueidentifier = NEWID();
DECLARE @FishId15    uniqueidentifier = NEWID();
DECLARE @MemoSmall15 uniqueidentifier = NEWID();
DECLARE @MemoBig15   uniqueidentifier = NEWID();
INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
VALUES (@FamilyId15, N'ut-family-15', 900015, SYSUTCDATETIME());
INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
VALUES (@FishId15, N'Walleye-ut15', N'Sander ut-vitreus-15', @FamilyId15, SYSUTCDATETIME(), SYSUTCDATETIME());

-- 2. execute unit test

-- smaller catch, in lb (~1.36 kg)
EXEC dbo.sp_add_catch_memo @id=@MemoSmall15, @lake_id=@Lake15, @userid=@Author15, @fish_id=@FishId15,
    @catch_date='2026-06-01', @weight=3, @weight_unit=N'lb';
-- bigger catch, in kg — this one should win regardless of unit
EXEC dbo.sp_add_catch_memo @id=@MemoBig15, @lake_id=@Lake15, @userid=@Author15, @fish_id=@FishId15,
    @catch_date='2026-06-15', @weight=2, @weight_unit=N'kg';
SELECT @SmallPb = catch_memo_is_pb FROM dbo.fn_catch_memo_list(@Lake15, @Author15, 0) WHERE catch_memo_id = @MemoSmall15;
SELECT @BigPb   = catch_memo_is_pb FROM dbo.fn_catch_memo_list(@Lake15, @Author15, 0) WHERE catch_memo_id = @MemoBig15;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @SmallPb IS NULL OR @SmallPb <> 0 OR @BigPb IS NULL OR @BigPb <> 1
   RAISERROR ('TEST 15 FAIL [%dms]: personal best not flagged on the heavier catch', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: personal best correctly flagged on the heavier catch'

ROLLBACK TRAN CM_Test15
GO

-- ============================================================================
-- TEST 16: fn_catch_memo_list never flags a personal best when the catch has no fish_id
-- ============================================================================
BEGIN TRAN CM_Test16
    declare @test_name sysname = N'CM_Test16 [fn_catch_memo_list] : never flags personal best without fish_id'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @FreeTextPb bit;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake16   uniqueidentifier = NEWID();
DECLARE @Author16 uniqueidentifier = NEWID();
DECLARE @Memo16   uniqueidentifier = NEWID();

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo @id=@Memo16, @lake_id=@Lake16, @userid=@Author16,
    @species=N'Unlisted Fish', @catch_date='2026-06-29', @weight=10, @weight_unit=N'kg';
SELECT @FreeTextPb = catch_memo_is_pb FROM dbo.fn_catch_memo_list(@Lake16, @Author16, 0) WHERE catch_memo_id = @Memo16;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @FreeTextPb IS NULL OR @FreeTextPb <> 0
   RAISERROR ('TEST 16 FAIL [%dms]: free-text species catch was flagged as personal best', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: free-text species catch never flagged as personal best'

ROLLBACK TRAN CM_Test16
GO

-- ============================================================================
-- TEST 17: fn_catch_weather_snapshot never attaches today's water temp to an old catch date
-- ============================================================================
BEGIN TRAN CM_Test17
    declare @test_name sysname = N'CM_Test17 [fn_catch_weather_snapshot] : never attaches today''s water temp to an old catch date'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @WaterTemp float;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake17    uniqueidentifier = NEWID();
DECLARE @Station17 uniqueidentifier = NEWID();
DECLARE @Mli17     varchar(64) = 'UT_MLI_017';
INSERT INTO dbo.Lake (Lake_id, locType, lake_name) VALUES (@Lake17, 1, N'UT Lake 17');
INSERT INTO dbo.WaterStation (id, mli, lakeName, locType, locName, locDesc, county, lat, lon, country, state, agency, stamp, supported, sid, lakeId)
VALUES (@Station17, @Mli17, N'UT Lake 17', 1, N'UT Station 17', N'UT Desc', N'UT County', 45.0, -75.0, 'CA', 'ON', 'TEST', GETUTCDATE(), 1, 900017, @Lake17);
-- CurrentWaterState has no history -- this is "right now", not "on the catch date"
INSERT INTO dbo.CurrentWaterState (mli, stamp, temperature, sid, iterstamp)
VALUES (@Mli17, GETUTCDATE(), 14.5, 900017, GETUTCDATE());

-- 2. execute unit test

-- a catch logged for a date weeks in the past must not get today's water reading attached
SELECT @WaterTemp = water_temp FROM dbo.fn_catch_weather_snapshot(@Lake17, DATEADD(DAY, -30, CAST(GETDATE() AS DATE)));

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @WaterTemp IS NOT NULL
   RAISERROR ('TEST 17 FAIL [%dms]: old catch date got a water temp attached', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: old catch date correctly got no water temp'

ROLLBACK TRAN CM_Test17
GO

-- ============================================================================
-- TEST 18: sp_add_catch_memo_photo stores description/author and fn_catch_memo_photo_list returns them
-- ============================================================================
BEGIN TRAN CM_Test18
    declare @test_name sysname = N'CM_Test18 [sp_add_catch_memo_photo] : stores description/author'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Desc nvarchar(500), @Auth nvarchar(200);
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake18   uniqueidentifier = NEWID();
DECLARE @Author18 uniqueidentifier = NEWID();
DECLARE @Memo18   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo18, @lake_id=@Lake18, @userid=@Author18,
    @species=N'Northern Pike', @catch_date='2026-06-29';

-- 2. execute unit test

EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo18, @userid=@Author18, @pic=0x89504E47,
    @label=N'pike.jpg', @ord=0, @description=N'Nice fight near the dock', @author=N'Jane Doe';
SELECT @Desc=catch_memo_photo_description, @Auth=catch_memo_photo_author
FROM dbo.fn_catch_memo_photo_list(@Memo18);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Desc IS NULL OR @Desc <> N'Nice fight near the dock' OR @Auth IS NULL OR @Auth <> N'Jane Doe'
   RAISERROR ('TEST 18 FAIL [%dms]: description/author not stored/returned as expected', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: photo description/author stored and returned'

ROLLBACK TRAN CM_Test18
GO

-- ============================================================================
-- TEST 19: sp_del_catch_memo_photo by a non-admin only hides the photo
-- ============================================================================
BEGIN TRAN CM_Test19
    declare @test_name sysname = N'CM_Test19 [sp_del_catch_memo_photo] : non-admin delete only hides the photo'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @RowCnt int, @Hidden bit, @ListedCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake19   uniqueidentifier = NEWID();
DECLARE @Author19 uniqueidentifier = NEWID();
DECLARE @Memo19   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo19, @lake_id=@Lake19, @userid=@Author19,
    @species=N'Northern Pike', @catch_date='2026-06-29';
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo19, @userid=@Author19, @pic=0x89504E47, @label=N'pike.jpg';
DECLARE @PhotoId19 uniqueidentifier;
SELECT @PhotoId19 = catch_memo_photo_id FROM dbo.catch_memo_photo WHERE catch_memo_photo_memoid = @Memo19;

-- 2. execute unit test

EXEC dbo.sp_del_catch_memo_photo @photo_id=@PhotoId19, @userid=@Author19, @is_admin=0;
SELECT @RowCnt = COUNT(*), @Hidden = MAX(CAST(catch_memo_photo_hidden AS int))
FROM dbo.catch_memo_photo WHERE catch_memo_photo_id = @PhotoId19;
SELECT @ListedCnt = COUNT(*) FROM dbo.fn_catch_memo_photo_list(@Memo19) WHERE catch_memo_photo_id = @PhotoId19;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @RowCnt IS NULL OR @RowCnt <> 1 OR @Hidden IS NULL OR @Hidden <> 1 OR @ListedCnt IS NULL OR @ListedCnt <> 0
   RAISERROR ('TEST 19 FAIL [%dms]: non-admin delete did not hide the photo as expected', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: non-admin delete hid the photo (row kept, excluded from listing)'

ROLLBACK TRAN CM_Test19
GO

-- ============================================================================
-- TEST 20: sp_del_catch_memo_photo by an admin physically deletes the photo
-- ============================================================================
BEGIN TRAN CM_Test20
    declare @test_name sysname = N'CM_Test20 [sp_del_catch_memo_photo] : admin delete physically removes the row'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @RowCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake20   uniqueidentifier = NEWID();
DECLARE @Author20 uniqueidentifier = NEWID();
DECLARE @Admin20  uniqueidentifier = NEWID();
DECLARE @Memo20   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo20, @lake_id=@Lake20, @userid=@Author20,
    @species=N'Northern Pike', @catch_date='2026-06-29';
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo20, @userid=@Author20, @pic=0x89504E47, @label=N'pike.jpg';
DECLARE @PhotoId20 uniqueidentifier;
SELECT @PhotoId20 = catch_memo_photo_id FROM dbo.catch_memo_photo WHERE catch_memo_photo_memoid = @Memo20;

-- 2. execute unit test

EXEC dbo.sp_del_catch_memo_photo @photo_id=@PhotoId20, @userid=@Admin20, @is_admin=1;
SELECT @RowCnt = COUNT(*) FROM dbo.catch_memo_photo WHERE catch_memo_photo_id = @PhotoId20;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @RowCnt IS NULL OR @RowCnt <> 0
   RAISERROR ('TEST 20 FAIL [%dms]: admin delete did not physically remove the row', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: admin delete physically removed the photo row'

ROLLBACK TRAN CM_Test20
GO

-- ============================================================================
-- TEST 21: sp_add_catch_memo_photo caps a memo at 3 non-hidden photos
-- ============================================================================
BEGIN TRAN CM_Test21
    declare @test_name sysname = N'CM_Test21 [sp_add_catch_memo_photo] : caps a memo at 3 photos'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @PhotoCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake21   uniqueidentifier = NEWID();
DECLARE @Author21 uniqueidentifier = NEWID();
DECLARE @Memo21   uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo21, @lake_id=@Lake21, @userid=@Author21,
    @species=N'Northern Pike', @catch_date='2026-06-29';

-- 2. execute unit test

-- 4 attempts, only 3 should ever land
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo21, @userid=@Author21, @pic=0x89504E47, @ord=0;
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo21, @userid=@Author21, @pic=0x89504E47, @ord=1;
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo21, @userid=@Author21, @pic=0x89504E47, @ord=2;
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Memo21, @userid=@Author21, @pic=0x89504E47, @ord=3;
SELECT @PhotoCnt = COUNT(*) FROM dbo.fn_catch_memo_photo_list(@Memo21);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @PhotoCnt IS NULL OR @PhotoCnt <> 3
   RAISERROR ('TEST 21 FAIL [%dms]: expected exactly 3 photos, got a different count', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 21 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 4th photo was rejected, memo capped at 3'

ROLLBACK TRAN CM_Test21
GO

-- ============================================================================
-- TEST 22: sp_NewGuidV7 returns distinct, correctly-versioned ids that sort in generation order
-- ============================================================================
BEGIN TRAN CM_Test22
    declare @test_name sysname = N'CM_Test22 [sp_NewGuidV7] : distinct, v7-versioned, time-ordered ids'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Id1 uniqueidentifier, @Id2 uniqueidentifier;
DECLARE @Ver1 char(1), @Ver2 char(1), @Var1 char(1), @Var2 char(1);
DECLARE @Ts1 char(8), @Ts2 char(8);
DECLARE @Ok bit = 1;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

EXEC dbo.sp_NewGuidV7 @Id1 OUTPUT;
WAITFOR DELAY '00:00:00.010';
EXEC dbo.sp_NewGuidV7 @Id2 OUTPUT;

-- 2. execute unit test

SET @Ver1 = SUBSTRING(CAST(@Id1 AS char(36)), 15, 1);   -- version nibble (3rd group, 1st char)
SET @Ver2 = SUBSTRING(CAST(@Id2 AS char(36)), 15, 1);
SET @Var1 = SUBSTRING(CAST(@Id1 AS char(36)), 20, 1);   -- variant nibble (4th group, 1st char)
SET @Var2 = SUBSTRING(CAST(@Id2 AS char(36)), 20, 1);
SET @Ts1  = SUBSTRING(CAST(@Id1 AS char(36)), 1, 8);    -- big-endian ms-timestamp prefix
SET @Ts2  = SUBSTRING(CAST(@Id2 AS char(36)), 1, 8);

IF @Id1 = @Id2 SET @Ok = 0;                             -- must be distinct
IF @Ver1 <> '7' OR @Ver2 <> '7' SET @Ok = 0;             -- RFC 9562 version 7
IF @Var1 NOT IN ('8','9','a','b') SET @Ok = 0;           -- RFC 9562 variant '10xx'
IF @Var2 NOT IN ('8','9','a','b') SET @Ok = 0;
IF @Ts2 < @Ts1 SET @Ok = 0;                              -- generated later -> string-sorts >= earlier

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
    SET @Ok = 0;
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Ok = 0
   RAISERROR ('TEST 22 FAIL [%dms]: sp_NewGuidV7 did not return distinct, v7-versioned, time-ordered ids', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 22 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two ids were distinct, version/variant correct, and time-ordered'

ROLLBACK TRAN CM_Test22
GO

-- ============================================================================
-- TEST 23: sp_clone_catch_memo copies most fields but never species/weight/length/photos
-- ============================================================================
BEGIN TRAN CM_Test23
    declare @test_name sysname = N'CM_Test23 [sp_clone_catch_memo] : clone excludes species/weight/length/photos'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Ok bit = 1;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake23   uniqueidentifier = NEWID();
DECLARE @Author23 uniqueidentifier = NEWID();
DECLARE @Cloner23 uniqueidentifier = NEWID();
DECLARE @Source23 uniqueidentifier = NEWID();
DECLARE @Clone23  uniqueidentifier = NEWID();

EXEC dbo.sp_add_catch_memo @id=@Source23, @lake_id=@Lake23, @userid=@Author23,
    @species=N'Bass, Smallmouth', @title=N'Great catch', @text=N'nice fight',
    @lat=43.1, @lon=-81.2, @method=N'trolling', @tackle=N'rod & reel', @lure=N'spoon',
    @catch_date='2026-06-29', @weight=2.5, @weight_unit=N'kg', @length=40, @length_unit=N'cm';
EXEC dbo.sp_add_catch_memo_photo @memo_id=@Source23, @userid=@Author23, @pic=0x89504E47;

-- 2. execute unit test

EXEC dbo.sp_clone_catch_memo @source_id=@Source23, @new_id=@Clone23, @userid=@Cloner23;

DECLARE @Species nvarchar(120), @FishId uniqueidentifier, @Weight float, @Length float
      , @Method nvarchar(200), @ClonedFrom uniqueidentifier, @Owner uniqueidentifier, @PhotoCnt int;

SELECT @Species=catch_memo_species, @FishId=catch_memo_fish_id, @Weight=catch_memo_weight,
       @Length=catch_memo_length, @Method=catch_memo_method, @ClonedFrom=catch_memo_cloned_from,
       @Owner=catch_memo_userid
FROM dbo.catch_memo WHERE catch_memo_id = @Clone23;

SELECT @PhotoCnt = COUNT(*) FROM dbo.catch_memo_photo WHERE catch_memo_photo_memoid = @Clone23;

IF @Species IS NOT NULL OR @FishId IS NOT NULL OR @Weight IS NOT NULL OR @Length IS NOT NULL SET @Ok = 0;
IF @Method <> N'trolling' SET @Ok = 0;
IF @ClonedFrom <> @Source23 SET @Ok = 0;
IF @Owner <> @Cloner23 SET @Ok = 0;
IF @PhotoCnt <> 0 SET @Ok = 0;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
    SET @Ok = 0;
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Ok = 0
   RAISERROR ('TEST 23 FAIL [%dms]: clone did not copy method/cloned_from/owner or wrongly carried species/weight/length/photos', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 23 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: clone copied method but excluded species/weight/length/photos'

ROLLBACK TRAN CM_Test23
GO

-- ============================================================================
-- TEST 24: sp_clone_catch_memo refuses a second clone while the first is unfinished
-- ============================================================================
BEGIN TRAN CM_Test24
    declare @test_name sysname = N'CM_Test24 [sp_clone_catch_memo] : blocked while a clone is unfinished'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Ok bit = 1;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake24    uniqueidentifier = NEWID();
DECLARE @Cloner24  uniqueidentifier = NEWID();
DECLARE @SourceA24 uniqueidentifier = NEWID();
DECLARE @SourceB24 uniqueidentifier = NEWID();
DECLARE @CloneA24  uniqueidentifier = NEWID();
DECLARE @CloneB24  uniqueidentifier = NEWID();

EXEC dbo.sp_add_catch_memo @id=@SourceA24, @lake_id=@Lake24, @userid=@Cloner24, @species=N'Walleye';
EXEC dbo.sp_add_catch_memo @id=@SourceB24, @lake_id=@Lake24, @userid=@Cloner24, @species=N'Pike';

-- 2. execute unit test

EXEC dbo.sp_clone_catch_memo @source_id=@SourceA24, @new_id=@CloneA24, @userid=@Cloner24;   -- unfinished clone #1
EXEC dbo.sp_clone_catch_memo @source_id=@SourceB24, @new_id=@CloneB24, @userid=@Cloner24;   -- should be refused

DECLARE @FirstExists bit, @SecondExists bit;
SET @FirstExists  = CASE WHEN EXISTS (SELECT 1 FROM dbo.catch_memo WHERE catch_memo_id = @CloneA24) THEN 1 ELSE 0 END;
SET @SecondExists = CASE WHEN EXISTS (SELECT 1 FROM dbo.catch_memo WHERE catch_memo_id = @CloneB24) THEN 1 ELSE 0 END;

IF @FirstExists <> 1 OR @SecondExists <> 0 SET @Ok = 0;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
    SET @Ok = 0;
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Ok = 0
   RAISERROR ('TEST 24 FAIL [%dms]: second clone should have been refused while the first is unfinished', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 24 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first clone created, second refused while unfinished'

ROLLBACK TRAN CM_Test24
GO

-- ============================================================================
-- TEST 25: cloning becomes possible again once the pending clone gets a species + photo
-- ============================================================================
BEGIN TRAN CM_Test25
    declare @test_name sysname = N'CM_Test25 [sp_clone_catch_memo] : allowed again once the clone is finished'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Ok bit = 1;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake25    uniqueidentifier = NEWID();
DECLARE @Cloner25  uniqueidentifier = NEWID();
DECLARE @SourceA25 uniqueidentifier = NEWID();
DECLARE @SourceB25 uniqueidentifier = NEWID();
DECLARE @CloneA25  uniqueidentifier = NEWID();
DECLARE @CloneB25  uniqueidentifier = NEWID();

EXEC dbo.sp_add_catch_memo @id=@SourceA25, @lake_id=@Lake25, @userid=@Cloner25, @species=N'Walleye';
EXEC dbo.sp_add_catch_memo @id=@SourceB25, @lake_id=@Lake25, @userid=@Cloner25, @species=N'Pike';
EXEC dbo.sp_clone_catch_memo @source_id=@SourceA25, @new_id=@CloneA25, @userid=@Cloner25;

-- 2. execute unit test

-- finish the first clone: give it a species and a photo
EXEC dbo.sp_add_catch_memo @id=@CloneA25, @lake_id=@Lake25, @userid=@Cloner25, @species=N'Walleye';
EXEC dbo.sp_add_catch_memo_photo @memo_id=@CloneA25, @userid=@Cloner25, @pic=0x89504E47;

EXEC dbo.sp_clone_catch_memo @source_id=@SourceB25, @new_id=@CloneB25, @userid=@Cloner25;   -- should now succeed

DECLARE @SecondExists bit;
SET @SecondExists = CASE WHEN EXISTS (SELECT 1 FROM dbo.catch_memo WHERE catch_memo_id = @CloneB25) THEN 1 ELSE 0 END;

IF @SecondExists <> 1 SET @Ok = 0;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
    SET @Ok = 0;
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Ok = 0
   RAISERROR ('TEST 25 FAIL [%dms]: second clone should have succeeded once the first was finished', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 25 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: cloning allowed again once the prior clone got a species + photo'

ROLLBACK TRAN CM_Test25
GO

-- ============================================================================
-- TEST 26: sp_clone_catch_memo refuses a private memo for a non-owner/non-admin
-- ============================================================================
BEGIN TRAN CM_Test26
    declare @test_name sysname = N'CM_Test26 [sp_clone_catch_memo] : private memo blocked for non-owner, allowed for owner/admin'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Ok bit = 1;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake26    uniqueidentifier = NEWID();
DECLARE @Owner26   uniqueidentifier = NEWID();
DECLARE @Other26   uniqueidentifier = NEWID();
DECLARE @Admin26   uniqueidentifier = NEWID();
DECLARE @Source26  uniqueidentifier = NEWID();
DECLARE @CloneA26  uniqueidentifier = NEWID();   -- attempted by non-owner (should fail)
DECLARE @CloneB26  uniqueidentifier = NEWID();   -- attempted by admin (should succeed)

EXEC dbo.sp_add_catch_memo @id=@Source26, @lake_id=@Lake26, @userid=@Owner26,
    @species=N'Muskellunge', @private=1;

-- 2. execute unit test

EXEC dbo.sp_clone_catch_memo @source_id=@Source26, @new_id=@CloneA26, @userid=@Other26, @is_admin=0;
EXEC dbo.sp_clone_catch_memo @source_id=@Source26, @new_id=@CloneB26, @userid=@Admin26, @is_admin=1;

DECLARE @NonOwnerExists bit, @AdminExists bit;
SET @NonOwnerExists = CASE WHEN EXISTS (SELECT 1 FROM dbo.catch_memo WHERE catch_memo_id = @CloneA26) THEN 1 ELSE 0 END;
SET @AdminExists    = CASE WHEN EXISTS (SELECT 1 FROM dbo.catch_memo WHERE catch_memo_id = @CloneB26) THEN 1 ELSE 0 END;

IF @NonOwnerExists <> 0 OR @AdminExists <> 1 SET @Ok = 0;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
    SET @Ok = 0;
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @Ok = 0
   RAISERROR ('TEST 26 FAIL [%dms]: private memo clone permission check failed', 16, -1, @ElapsedMs)
ELSE
    print 'TEST 26 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: private memo blocked for non-owner, allowed for admin'

ROLLBACK TRAN CM_Test26
GO

-- ============================================================================
-- TEST 27: fn_catch_memo_list hides an incomplete public memo (no catch date
--          AND no visible photo) from guests/other users, shows it to author/admin
-- ============================================================================
BEGIN TRAN CM_Test27
    declare @test_name sysname = N'CM_Test27 [fn_catch_memo_list] : incomplete public memo (no date, no photo) is author/admin-only'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @GuestCnt int, @OtherCnt int, @AuthorCnt int, @AdminCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test
--    Public memo (private = 0) but a bare stub: no catch date and no photo.

DECLARE @Lake27      uniqueidentifier = NEWID();
DECLARE @Author27    uniqueidentifier = NEWID();
DECLARE @OtherUser27 uniqueidentifier = NEWID();
DECLARE @Admin27     uniqueidentifier = NEWID();
DECLARE @Memo27      uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@Memo27, @lake_id=@Lake27, @userid=@Author27,
    @species=N'Northern Pike', @catch_date=NULL, @private=0;

-- 2. execute unit test

SELECT @GuestCnt  = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake27, NULL,         0) WHERE catch_memo_id = @Memo27;
SELECT @OtherCnt  = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake27, @OtherUser27, 0) WHERE catch_memo_id = @Memo27;
SELECT @AuthorCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake27, @Author27,    0) WHERE catch_memo_id = @Memo27;
SELECT @AdminCnt  = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake27, @Admin27,     1) WHERE catch_memo_id = @Memo27;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @GuestCnt <> 0 OR @OtherCnt <> 0 OR @AuthorCnt <> 1 OR @AdminCnt <> 1
   RAISERROR ('TEST 27 FAIL [%dms]: incomplete public memo visibility wrong (guest=%d other=%d author=%d admin=%d)', 16, -1, @ElapsedMs, @GuestCnt, @OtherCnt, @AuthorCnt, @AdminCnt)
ELSE
    print 'TEST 27 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: incomplete public memo hidden from guest/other, visible to author/admin'

ROLLBACK TRAN CM_Test27
GO

-- ============================================================================
-- TEST 28: fn_catch_memo_list shows a public memo to everyone once it has a
--          catch date OR a non-hidden photo; a hidden-only photo + no date stays hidden
-- ============================================================================
BEGIN TRAN CM_Test28
    declare @test_name sysname = N'CM_Test28 [fn_catch_memo_list] : a catch date or a visible photo makes a public memo publicly visible'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @DatedCnt int, @PhotoCnt int, @HiddenOnlyCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

-- 1. prepare data for unit test

DECLARE @Lake28   uniqueidentifier = NEWID();
DECLARE @Author28 uniqueidentifier = NEWID();

-- (a) public memo with a catch date but no photo -> visible to a guest
DECLARE @MemoDated28 uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@MemoDated28, @lake_id=@Lake28, @userid=@Author28,
    @species=N'Northern Pike', @catch_date='2026-06-29', @private=0;

-- (b) public memo with no date but a non-hidden photo -> visible to a guest
DECLARE @MemoPhoto28 uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@MemoPhoto28, @lake_id=@Lake28, @userid=@Author28,
    @species=N'Northern Pike', @catch_date=NULL, @private=0;
EXEC dbo.sp_add_catch_memo_photo @memo_id=@MemoPhoto28, @userid=@Author28, @pic=0x89504E47, @label=N'pike.jpg';

-- (c) public memo with no date whose only photo is hidden -> still hidden from a guest
DECLARE @MemoHidden28 uniqueidentifier = NEWID();
EXEC dbo.sp_add_catch_memo @id=@MemoHidden28, @lake_id=@Lake28, @userid=@Author28,
    @species=N'Northern Pike', @catch_date=NULL, @private=0;
EXEC dbo.sp_add_catch_memo_photo @memo_id=@MemoHidden28, @userid=@Author28, @pic=0x89504E47, @label=N'hidden.jpg';
DECLARE @HiddenPhoto28 uniqueidentifier;
SELECT @HiddenPhoto28 = catch_memo_photo_id FROM dbo.catch_memo_photo WHERE catch_memo_photo_memoid = @MemoHidden28;
EXEC dbo.sp_del_catch_memo_photo @photo_id=@HiddenPhoto28, @userid=@Author28, @is_admin=0;  -- hides it

-- 2. execute unit test (all as a guest)

SELECT @DatedCnt      = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake28, NULL, 0) WHERE catch_memo_id = @MemoDated28;
SELECT @PhotoCnt      = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake28, NULL, 0) WHERE catch_memo_id = @MemoPhoto28;
SELECT @HiddenOnlyCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake28, NULL, 0) WHERE catch_memo_id = @MemoHidden28;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE()   AS ErrorState
         , @test_name     AS ErrorProcedure, ERROR_LINE()     AS ErrorLine,     ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 3. result verification

IF @DatedCnt <> 1 OR @PhotoCnt <> 1 OR @HiddenOnlyCnt <> 0
   RAISERROR ('TEST 28 FAIL [%dms]: public completeness gate wrong (dated=%d photo=%d hiddenOnly=%d)', 16, -1, @ElapsedMs, @DatedCnt, @PhotoCnt, @HiddenOnlyCnt)
ELSE
    print 'TEST 28 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: a catch date or visible photo makes a public memo visible; a hidden-only photo does not'

ROLLBACK TRAN CM_Test28
GO
