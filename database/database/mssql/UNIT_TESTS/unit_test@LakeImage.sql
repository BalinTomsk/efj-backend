/*
  Unit tests for dbo.sp_add_lake_image (called by ~/Editor/LakeEditor.aspx btnBriefUpload_Click).
  Uses real table dbo.lake_image (lake_image_ownerid has no FK, so no parent setup needed).
  Transaction is rolled back at end - database state fully restored.

  Dedup is GLOBAL by picture hash: UK_lake_image is UNIQUE on lake_image_hash alone.

  TEST 1 - New picture for an owner -> inserted, one row for that hash
  TEST 2 - Same picture re-uploaded (same owner) -> no-op, no duplicate-key error, still one row
  TEST 3 - Same picture uploaded for a DIFFERENT owner -> no-op (global hash dedup), still one row
  TEST 4 - A different picture for the same owner -> inserted (gallery = many-per-owner)
*/
SET NOCOUNT ON;

DECLARE @OwnerA    uniqueidentifier = NEWID();
DECLARE @OwnerB    uniqueidentifier = NEWID();
DECLARE @Pic1      varbinary(max)   = 0xFFD8AA01;
DECLARE @Pic2      varbinary(max)   = 0xFFD8AA02;
DECLARE @Hash1     varbinary(256)   = HASHBYTES('MD5', 0xFFD8AA01);
DECLARE @Hash2     varbinary(256)   = HASHBYTES('MD5', 0xFFD8AA02);
DECLARE @ret       TABLE (lake_image_id int, inserted bit);
DECLARE @ins       bit;
DECLARE @cnt       int;
DECLARE @ownerOk   bit;
DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: New picture -> inserted, exactly one row for that hash
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM @ret;
    INSERT INTO @ret EXEC dbo.sp_add_lake_image @lake_id=@OwnerA, @image=@Pic1,
        @source=N'ut', @author=N'ut', @link=N'', @hash=@Hash1, @stamp='2026-01-01';
    SELECT @ins = inserted FROM @ret;
    SELECT @cnt = COUNT(*) FROM dbo.lake_image WHERE lake_image_hash = @Hash1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ins = 1 AND @cnt = 1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: new picture inserted (inserted=1, 1 row)';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted=1 & 1 row, got inserted=' + CAST(ISNULL(@ins,-1) AS varchar) + ', rows=' + CAST(@cnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: Re-upload same picture, same owner -> no-op, no error, still one row
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM @ret;
    INSERT INTO @ret EXEC dbo.sp_add_lake_image @lake_id=@OwnerA, @image=@Pic1,
        @source=N'ut', @author=N'ut', @link=N'', @hash=@Hash1, @stamp='2026-01-01';
    SELECT @ins = inserted FROM @ret;
    SELECT @cnt = COUNT(*) FROM dbo.lake_image WHERE lake_image_hash = @Hash1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ins = 0 AND @cnt = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: duplicate upload is a no-op (inserted=0, still 1 row, no error)';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted=0 & 1 row, got inserted=' + CAST(ISNULL(@ins,-1) AS varchar) + ', rows=' + CAST(@cnt AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: Same picture, DIFFERENT owner -> no-op (global hash dedup); row stays with OwnerA
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM @ret;
    INSERT INTO @ret EXEC dbo.sp_add_lake_image @lake_id=@OwnerB, @image=@Pic1,
        @source=N'ut', @author=N'ut', @link=N'', @hash=@Hash1, @stamp='2026-01-01';
    SELECT @ins = inserted FROM @ret;
    SELECT @cnt = COUNT(*) FROM dbo.lake_image WHERE lake_image_hash = @Hash1;
    SELECT @ownerOk = 1 FROM dbo.lake_image WHERE lake_image_hash = @Hash1 AND lake_image_ownerid = @OwnerA;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ins = 0 AND @cnt = 1 AND @ownerOk = 1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: same picture for another owner is a no-op (global hash dedup)';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted=0, 1 row, still OwnerA; got inserted=' + CAST(ISNULL(@ins,-1) AS varchar) + ', rows=' + CAST(@cnt AS varchar) + ', ownerOk=' + CAST(ISNULL(@ownerOk,0) AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: A different picture for the same owner -> inserted (many-per-owner gallery)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM @ret;
    INSERT INTO @ret EXEC dbo.sp_add_lake_image @lake_id=@OwnerA, @image=@Pic2,
        @source=N'ut', @author=N'ut', @link=N'', @hash=@Hash2, @stamp='2026-01-01';
    SELECT @ins = inserted FROM @ret;
    SELECT @cnt = COUNT(*) FROM dbo.lake_image WHERE lake_image_ownerid = @OwnerA;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ins = 1 AND @cnt = 2
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: a different picture adds a second gallery row (inserted=1, 2 rows for owner)';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted=1 & 2 rows, got inserted=' + CAST(ISNULL(@ins,-1) AS varchar) + ', rows=' + CAST(@cnt AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
