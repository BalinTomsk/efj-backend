/*
  Unit tests for the Catch Log (catch memo) feature: dbo.catch_memo, dbo.catch_pending_fish,
  dbo.sp_add_catch_memo, dbo.fn_catch_memo_list, dbo.fn_catch_memo_get,
  dbo.sp_add_catch_pending_fish, dbo.sp_set_catch_pending_fish_status,
  dbo.fn_catch_pending_fish_list, dbo.fn_lake_fish_list.

  Uses real tables (catch_memo / catch_pending_fish have no FKs, so no parent setup is
  needed for them; lake_fish needs a real fish + fish_family row as fixtures for the
  pending-fish dedup tests). Transaction is rolled back at end - database state restored.

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
*/
SET NOCOUNT ON;

DECLARE @Lake        uniqueidentifier = NEWID();
DECLARE @Author      uniqueidentifier = NEWID();
DECLARE @OtherUser   uniqueidentifier = NEWID();
DECLARE @Admin       uniqueidentifier = NEWID();
DECLARE @MemoId      uniqueidentifier = NEWID();
DECLARE @FamilyId    uniqueidentifier = NEWID();
DECLARE @FishId      uniqueidentifier = NEWID();
DECLARE @tStart      datetime2;
DECLARE @ElapsedMs   int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- fixtures for the pending-fish tests (fish / lake_fish are real, FK'd tables)
    INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
    VALUES (@FamilyId, N'ut-family', 900001, SYSUTCDATETIME());
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
    VALUES (@FishId, N'Walleye-ut', N'Sander ut-vitreus', @FamilyId, SYSUTCDATETIME(), SYSUTCDATETIME());
    INSERT INTO dbo.lake_fish (lake_Id, fish_Id, created, lake_fish_id)
    VALUES (@Lake, @FishId, SYSUTCDATETIME(), NEWID());

    -- ----------------------------------------------------------------
    -- TEST 1: insert stores weight/length/units/released/private
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_memo @id=@MemoId, @lake_id=@Lake, @userid=@Author,
        @species=N'Northern Pike', @text=N'nice one', @catch_date='2026-06-29',
        @weight=3.2, @weight_unit=N'kg', @length=65, @length_unit=N'cm',
        @released=1, @private=1;
    DECLARE @W float, @WU nvarchar(8), @L float, @LU nvarchar(8), @Rel bit, @Priv bit;
    SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
           @LU=catch_memo_length_unit, @Rel=catch_memo_released, @Priv=catch_memo_private
    FROM dbo.catch_memo WHERE catch_memo_id = @MemoId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @W = 3.2 AND @WU = N'kg' AND @L = 65 AND @LU = N'cm' AND @Rel = 1 AND @Priv = 1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stored weight/length/units/released/private';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: unexpected stored values';

    -- ----------------------------------------------------------------
    -- TEST 2: upsert (same @id) updates the stored values
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_memo @id=@MemoId, @lake_id=@Lake, @userid=@Author,
        @species=N'Northern Pike', @text=N'nice one', @catch_date='2026-06-29',
        @weight=7, @weight_unit=N'lb', @length=null, @length_unit=null,
        @released=null, @private=0;
    SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
           @Rel=catch_memo_released, @Priv=catch_memo_private
    FROM dbo.catch_memo WHERE catch_memo_id = @MemoId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @W = 7 AND @WU = N'lb' AND @L IS NULL AND @Rel IS NULL AND @Priv = 0
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: upsert updated weight/unit/length/released/private';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: upsert did not update as expected';

    -- restore a private memo for the visibility tests below
    EXEC dbo.sp_add_catch_memo @id=@MemoId, @lake_id=@Lake, @userid=@Author,
        @species=N'Northern Pike', @catch_date='2026-06-29',
        @weight=3.2, @weight_unit=N'kg', @length=65, @length_unit=N'cm',
        @released=1, @private=1;

    -- ----------------------------------------------------------------
    -- TEST 3: fn_catch_memo_list hides a private memo from a guest / another user
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @GuestCnt int, @OtherCnt int;
    SELECT @GuestCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake, NULL, 0) WHERE catch_memo_id = @MemoId;
    SELECT @OtherCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake, @OtherUser, 0) WHERE catch_memo_id = @MemoId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @GuestCnt = 0 AND @OtherCnt = 0
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: private memo hidden from guest and other user';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: guest=' + CAST(@GuestCnt AS varchar) + ', other=' + CAST(@OtherCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: fn_catch_memo_list shows a private memo to author and admin
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @AuthorCnt int, @AdminCnt int;
    SELECT @AuthorCnt = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake, @Author, 0) WHERE catch_memo_id = @MemoId;
    SELECT @AdminCnt  = COUNT(*) FROM dbo.fn_catch_memo_list(@Lake, @Admin, 1)  WHERE catch_memo_id = @MemoId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @AuthorCnt = 1 AND @AdminCnt = 1
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: private memo visible to author and admin';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: author=' + CAST(@AuthorCnt AS varchar) + ', admin=' + CAST(@AdminCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 5: fn_catch_memo_get returns weight/length/released/private
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SELECT @W=catch_memo_weight, @WU=catch_memo_weight_unit, @L=catch_memo_length,
           @LU=catch_memo_length_unit, @Rel=catch_memo_released, @Priv=catch_memo_private
    FROM dbo.fn_catch_memo_get(@MemoId, @Author, 0);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @W = 3.2 AND @WU = N'kg' AND @L = 65 AND @LU = N'cm' AND @Rel = 1 AND @Priv = 1
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_catch_memo_get returned correct new-column values';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_catch_memo_get returned unexpected values';

    -- ----------------------------------------------------------------
    -- TEST 6: non-author update is blocked (author/lock guard still enforced)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_memo @id=@MemoId, @lake_id=@Lake, @userid=@OtherUser,
        @weight=999, @private=0, @is_admin=0;
    SELECT @W=catch_memo_weight, @Priv=catch_memo_private FROM dbo.catch_memo WHERE catch_memo_id = @MemoId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @W = 3.2 AND @Priv = 1
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: non-author update was blocked (values unchanged)';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: non-author update was NOT blocked';

    -- ----------------------------------------------------------------
    -- TEST 7: sp_add_catch_pending_fish queues a new (unlisted) species
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake, @userid=@Author, @fish_name=N'Muskellunge-ut';
    DECLARE @PendCnt int;
    SELECT @PendCnt = COUNT(*) FROM dbo.catch_pending_fish
    WHERE catch_pending_fish_lake_id = @Lake AND catch_pending_fish_name = N'Muskellunge-ut';
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @PendCnt = 1
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: new species queued in catch_pending_fish';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1 queued row, got ' + CAST(@PendCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 8: sp_add_catch_pending_fish is a no-op for a species already on the lake
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake, @userid=@Author, @fish_name=N'Walleye-ut';
    DECLARE @KnownCnt int;
    SELECT @KnownCnt = COUNT(*) FROM dbo.catch_pending_fish
    WHERE catch_pending_fish_lake_id = @Lake AND catch_pending_fish_name = N'Walleye-ut';
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @KnownCnt = 0
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: already-known species was not queued';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0 queued rows, got ' + CAST(@KnownCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 9: sp_add_catch_pending_fish dedups a repeat suggestion
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_catch_pending_fish @lake_id=@Lake, @userid=@OtherUser, @fish_name=N'Muskellunge-ut';
    DECLARE @DupPendCnt int;
    SELECT @DupPendCnt = COUNT(*) FROM dbo.catch_pending_fish
    WHERE catch_pending_fish_lake_id = @Lake AND catch_pending_fish_name = N'Muskellunge-ut';
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @DupPendCnt = 1
        PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: repeat suggestion did not duplicate the queue row';
    ELSE
        PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1 queued row, got ' + CAST(@DupPendCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 10: sp_set_catch_pending_fish_status marks a suggestion approved
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @PendId int;
    SELECT @PendId = catch_pending_fish_id FROM dbo.catch_pending_fish
    WHERE catch_pending_fish_lake_id = @Lake AND catch_pending_fish_name = N'Muskellunge-ut';
    EXEC dbo.sp_set_catch_pending_fish_status @id=@PendId, @status=1, @admin_userid=@Admin;
    DECLARE @Status tinyint, @DecidedBy uniqueidentifier;
    SELECT @Status=catch_pending_fish_status, @DecidedBy=catch_pending_fish_decided_by
    FROM dbo.catch_pending_fish WHERE catch_pending_fish_id = @PendId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Status = 1 AND @DecidedBy = @Admin
        PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: suggestion marked approved by admin';
    ELSE
        PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: status/decided_by not as expected';

    -- ----------------------------------------------------------------
    -- TEST 11: fn_lake_fish_list returns the species assigned to the water body
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @LakeFishCnt int;
    SELECT @LakeFishCnt = COUNT(*) FROM dbo.fn_lake_fish_list(@Lake) WHERE fish_id = @FishId AND fish_name = N'Walleye-ut';
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @LakeFishCnt = 1
        PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_fish_list returned the assigned species';
    ELSE
        PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1 row, got ' + CAST(@LakeFishCnt AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
