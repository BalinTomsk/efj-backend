/*
  Unit tests for dbo.sp_add_lake_map, dbo.fn_lake_map_handler, dbo.fn_lake_map_list.
  Uses real table dbo.lake_map (lake_map_ownerid has no FK, so no parent setup needed).
  Transaction is rolled back at end - database state fully restored.

  TEST 1 - Two DIFFERENT files for the same owner -> two rows (multi-map works)
  TEST 2 - Same file re-added to the same owner -> no duplicate (per-owner dedup)
  TEST 3 - Same file added to a DIFFERENT owner -> allowed (composite uniqueness)
  TEST 4 - Two different external links for one owner -> two rows
  TEST 5 - fn_lake_map_handler returns the correct image binary
  TEST 6 - fn_lake_map_list returns the expected rows / metadata
*/
SET NOCOUNT ON;

DECLARE @OwnerA      uniqueidentifier = NEWID();
DECLARE @OwnerB      uniqueidentifier = NEWID();
DECLARE @File1       varbinary(max)   = 0xA001;
DECLARE @File2       varbinary(max)   = 0xA002;
DECLARE @Map1Id      int;
DECLARE @tStart      datetime2;
DECLARE @ElapsedMs   int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: Two distinct files for the same owner -> two rows
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerA, @image=@File1, @type=1, @kind=1,
        @source=N'ut', @author=N'ut', @link=N'', @label=N'one.jpg', @location=N'loc',
        @lat=45.0, @lon=-75.0, @tag=N'tag', @stamp=N'2026-01-01';
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerA, @image=@File2, @type=8, @kind=2,
        @source=N'ut', @author=N'ut', @link=N'', @label=N'two.pdf', @location=N'loc',
        @lat=45.0, @lon=-75.0, @tag=N'tag', @stamp=N'2026-01-01';
    DECLARE @Cnt1 int;
    SELECT @Cnt1 = COUNT(*) FROM dbo.lake_map WHERE lake_map_ownerid = @OwnerA;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Cnt1 = 2
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two distinct files -> two rows for owner';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2 rows, got ' + CAST(@Cnt1 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: Re-add File1 to the same owner -> still one row for that file
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerA, @image=@File1, @type=1, @kind=1,
        @source=N'ut', @author=N'ut', @link=N'', @label=N'one.jpg', @location=N'loc',
        @lat=45.0, @lon=-75.0, @tag=N'tag', @stamp=N'2026-01-01';
    DECLARE @DupFile1 int;
    SELECT @DupFile1 = COUNT(*) FROM dbo.lake_map
    WHERE lake_map_ownerid = @OwnerA AND lake_map_hash = HASHBYTES('SHA1', @File1 + CAST(N'' AS varbinary(800)));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @DupFile1 = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: re-adding same file is a no-op (1 row)';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1 row, got ' + CAST(@DupFile1 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: Same file attached to a DIFFERENT owner -> allowed
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerB, @image=@File1, @type=1, @kind=1,
        @source=N'ut', @author=N'ut', @link=N'', @label=N'one.jpg', @location=N'loc',
        @lat=45.0, @lon=-75.0, @tag=N'tag', @stamp=N'2026-01-01';
    DECLARE @CrossOwner int;
    SELECT @CrossOwner = COUNT(*) FROM dbo.lake_map
    WHERE lake_map_hash = HASHBYTES('SHA1', @File1 + CAST(N'' AS varbinary(800)));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @CrossOwner = 2
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: same file allowed for two owners (2 rows total)';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2 rows, got ' + CAST(@CrossOwner AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: Two distinct external links for OwnerB -> two link rows
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerB, @image=NULL, @type=0, @kind=4,
        @source=N'ut', @author=N'ut', @link=N'http://maps.example/a', @label=N'', @location=N'loc',
        @lat=0, @lon=0, @tag=N'tag', @stamp=N'2026-01-01';
    EXEC dbo.sp_add_lake_map @lake_id=@OwnerB, @image=NULL, @type=0, @kind=4,
        @source=N'ut', @author=N'ut', @link=N'http://maps.example/b', @label=N'', @location=N'loc',
        @lat=0, @lon=0, @tag=N'tag', @stamp=N'2026-01-01';
    DECLARE @LinkCnt int;
    SELECT @LinkCnt = COUNT(*) FROM dbo.lake_map WHERE lake_map_ownerid = @OwnerB AND lake_map_type = 0;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @LinkCnt = 2
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two distinct links -> two rows';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2 link rows, got ' + CAST(@LinkCnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 5: fn_lake_map_handler returns correct binary
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SELECT @Map1Id = lake_map_id FROM dbo.lake_map
    WHERE lake_map_ownerid = @OwnerA AND lake_map_hash = HASHBYTES('SHA1', @File1 + CAST(N'' AS varbinary(800)));
    DECLARE @Returned varbinary(max) = dbo.fn_lake_map_handler(@OwnerA, @Map1Id);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Returned = @File1
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_map_handler returned correct bytes';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_map_handler returned unexpected value';

    -- ----------------------------------------------------------------
    -- TEST 6: fn_lake_map_list returns the right rows + metadata
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @ListCnt int, @LabelOk bit = 0;
    SELECT @ListCnt = COUNT(*) FROM dbo.fn_lake_map_list(@OwnerA);
    SELECT @LabelOk = 1 FROM dbo.fn_lake_map_list(@OwnerA)
    WHERE lake_map_id = @Map1Id AND lake_map_label = N'one.jpg' AND lake_map_type = 1 AND lake_map_kind = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ListCnt = 2 AND @LabelOk = 1
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_lake_map_list returned 2 rows with correct metadata';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: list count=' + CAST(@ListCnt AS varchar) + ', labelOk=' + CAST(@LabelOk AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
