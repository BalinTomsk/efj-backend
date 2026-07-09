-- Created by GitHub Copilot in SSMS - review carefully before executing
/*
  Unit tests for dbo.sp_add_fish_image, dbo.fn_fish_image_handler, dbo.fn_fish_image_info.
  Uses real tables: dbo.fish, dbo.fish_family, dbo.fish_zoo, dbo.fish_image.
  Transaction is rolled back at end — database state fully restored.

  TEST 1 – New distinct image creates a row in fish_image
  TEST 2 – Duplicate image (same binary hash) reuses existing row; no duplicate
  TEST 3 – fish_zoo.fish_zoo_image FK updated to the correct image id
  TEST 4 – NULL fish_id is a no-op; nothing inserted
  TEST 5 – fn_fish_image_handler returns the correct image binary
  TEST 6 – fn_fish_image_info metadata matches expected VALUES table
*/
SET NOCOUNT ON;

DECLARE @TestFamilyId   uniqueidentifier = NEWID();
DECLARE @TestFishId     uniqueidentifier = NEWID();
DECLARE @TestImage1     varbinary(max)   = 0xFF01;
DECLARE @TestImage2     varbinary(max)   = 0xFF02;
DECLARE @ImageId1       int;
DECLARE @ImageIdReuse   int;
DECLARE @tStart         datetime2;
DECLARE @ElapsedMs      int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Setup: minimal parent rows required by FK chain (sid is IDENTITY — omitted)
    INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
    VALUES (@TestFamilyId, N'__TEST_FAMILY__', -999, GETUTCDATE());

    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
    VALUES (@TestFishId, N'__TEST_FISH__', N'Testus fishus', @TestFamilyId, GETUTCDATE(), GETUTCDATE());

    INSERT INTO dbo.fish_zoo (fish_id, stamp)
    VALUES (@TestFishId, GETUTCDATE());

    -- ----------------------------------------------------------------
    -- TEST 1: New image → row created in fish_image
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_fish_image
        @fish_id = @TestFishId, @image = @TestImage1, @tablename = N'fish_zoo', @colname = N'fish_zoo_image',
        @gender = 1, @source = N'unit-test', @author = N'copilot', @link = N'http://test',
        @label = N'test-label', @location = N'test-location', @lat = 45.0, @lon = -75.0,
        @tag = N'test-tag', @stamp = N'2026-01-01';
    SELECT @ImageId1 = fish_image_id FROM dbo.fish_image
    WHERE fish_id = @TestFishId AND fish_image_hash = HASHBYTES('SHA1', @TestImage1);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ImageId1 IS NOT NULL
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: New image row created in fish_image (id=' + CAST(@ImageId1 AS varchar) + ')';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: Expected row in fish_image was not found';

    -- ----------------------------------------------------------------
    -- TEST 2: Same binary re-submitted → existing row reused, no duplicate
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_fish_image
        @fish_id = @TestFishId, @image = @TestImage1, @tablename = N'fish_zoo', @colname = N'fish_zoo_image',
        @gender = 0, @source = N'unit-test', @author = N'copilot', @link = N'http://test',
        @label = N'test-label', @location = N'test-location', @lat = 45.0, @lon = -75.0,
        @tag = N'test-tag', @stamp = N'2026-01-01';
    DECLARE @DupCount int;
    SELECT @DupCount     = COUNT(*)      FROM dbo.fish_image WHERE fish_image_hash = HASHBYTES('SHA1', @TestImage1);
    SELECT @ImageIdReuse = fish_image_id FROM dbo.fish_image WHERE fish_image_hash = HASHBYTES('SHA1', @TestImage1);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ImageIdReuse = @ImageId1 AND @DupCount = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Duplicate image reused existing row (id=' + CAST(@ImageIdReuse AS varchar) + ')';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: Expected id=' + ISNULL(CAST(@ImageId1 AS varchar), 'NULL')
            + ', got=' + ISNULL(CAST(@ImageIdReuse AS varchar), 'NULL')
            + ', row count=' + CAST(@DupCount AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: fish_zoo.fish_zoo_image FK updated
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @ZooImageId int;
    SELECT @ZooImageId = fish_zoo_image FROM dbo.fish_zoo WHERE fish_id = @TestFishId;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ZooImageId = @ImageId1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fish_zoo.fish_zoo_image updated correctly (id=' + CAST(@ZooImageId AS varchar) + ')';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fish_zoo.fish_zoo_image expected=' + ISNULL(CAST(@ImageId1 AS varchar), 'NULL')
            + ', actual=' + ISNULL(CAST(@ZooImageId AS varchar), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 4: NULL @fish_id → no-op
    -- ----------------------------------------------------------------
    DECLARE @CountBefore int, @CountAfter int;
    SELECT @CountBefore = COUNT(*) FROM dbo.fish_image;
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_fish_image
        @fish_id = NULL, @image = @TestImage2, @tablename = N'fish_zoo', @colname = N'fish_zoo_image',
        @gender = 0, @source = N'unit-test', @author = N'copilot', @link = N'http://test',
        @label = N'test-label', @location = N'test-location', @lat = 0.0, @lon = 0.0,
        @tag = N'test-tag', @stamp = N'2026-01-01';
    SELECT @CountAfter = COUNT(*) FROM dbo.fish_image;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @CountAfter = @CountBefore
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL fish_id -> no row inserted in fish_image';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL fish_id should not insert; count went from '
            + CAST(@CountBefore AS varchar) + ' to ' + CAST(@CountAfter AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 5: fn_fish_image_handler returns correct binary
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @ReturnedImage varbinary(max);
    SET @ReturnedImage = dbo.fn_fish_image_handler(@TestFishId, @ImageId1);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @ReturnedImage = @TestImage1
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_fish_image_handler returned correct image binary';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_fish_image_handler returned unexpected value';

    -- ----------------------------------------------------------------
    -- TEST 6: fn_fish_image_info metadata matched via VALUES inline table
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @InfoPass bit = 0;
    SELECT @InfoPass = 1
    FROM dbo.fn_fish_image_info(@TestFishId, @ImageId1) AS actual
    INNER JOIN (
        VALUES (
            CAST(N'unit-test'     AS nvarchar(255)),
            CAST(N'copilot'       AS nvarchar(255)),
            CAST(N'http://test'   AS nvarchar(255)),
            CAST(N'test-label'    AS nvarchar(255)),
            CAST(N'test-location' AS nvarchar(255))
        )
    ) AS expected (fish_image_source, fish_image_author, fish_image_link, fish_image_label, fish_image_location)
        ON  actual.fish_image_source   = expected.fish_image_source
        AND actual.fish_image_author   = expected.fish_image_author
        AND actual.fish_image_link     = expected.fish_image_link
        AND actual.fish_image_label    = expected.fish_image_label
        AND actual.fish_image_location = expected.fish_image_location;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @InfoPass = 1
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_fish_image_info returned correct metadata';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_fish_image_info metadata mismatch';

    -- ----------------------------------------------------------------
    -- TEST 7: fn_edit_fish_general returns the CURRENT picture (fish_zoo.fish_zoo_image =
    --         last uploaded), NOT the image with the latest user-entered fish_image_stamp.
    --         Repro: upload Image_A dated 2026-05-01, then Image_B dated 2026-01-01 (Image_B is
    --         uploaded LAST, so it becomes the current fish_zoo_image). The General tab / viewer
    --         must show Image_B (matching Habitat/Zoology), not Image_A.
    -- ----------------------------------------------------------------
    DECLARE @ImgA int, @ImgB int, @GeneralImgId int;
    EXEC dbo.sp_add_fish_image
        @fish_id = @TestFishId, @image = 0xAA71, @tablename = N'fish_zoo', @colname = N'fish_zoo_image',
        @gender = 1, @source = N'ut', @author = N'ut', @link = N'x', @label = N'A',
        @location = N'x', @lat = 0, @lon = 0, @tag = N'x', @stamp = N'2026-05-01';   -- LATER date
    SELECT @ImgA = fish_image_id FROM dbo.fish_image WHERE fish_image_hash = HASHBYTES('SHA1', CAST(0xAA71 AS varbinary(max)));

    EXEC dbo.sp_add_fish_image
        @fish_id = @TestFishId, @image = 0xBB72, @tablename = N'fish_zoo', @colname = N'fish_zoo_image',
        @gender = 1, @source = N'ut', @author = N'ut', @link = N'x', @label = N'B',
        @location = N'x', @lat = 0, @lon = 0, @tag = N'x', @stamp = N'2026-01-01';   -- EARLIER date, uploaded LAST
    SELECT @ImgB = fish_image_id FROM dbo.fish_image WHERE fish_image_hash = HASHBYTES('SHA1', CAST(0xBB72 AS varbinary(max)));

    SET @tStart = SYSUTCDATETIME();
    SELECT @GeneralImgId = fish_image_id FROM dbo.fn_edit_fish_general(CAST(@TestFishId AS varchar(36)));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @GeneralImgId = @ImgB
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_edit_fish_general returned current fish_zoo_image (last uploaded, id=' + CAST(@ImgB AS varchar) + ')';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected last-uploaded id=' + ISNULL(CAST(@ImgB AS varchar), 'NULL')
            + ' (=fish_zoo_image), got=' + ISNULL(CAST(@GeneralImgId AS varchar), 'NULL') + ' (stale stamp-ordered image)';

    -- ----------------------------------------------------------------
    -- TEST 8: fallback — no fish_zoo_image set → newest fish_image by insert order (identity),
    --         still independent of the user-entered stamp.
    -- ----------------------------------------------------------------
    UPDATE dbo.fish_zoo SET fish_zoo_image = NULL WHERE fish_id = @TestFishId;
    SET @tStart = SYSUTCDATETIME();
    SELECT @GeneralImgId = fish_image_id FROM dbo.fn_edit_fish_general(CAST(@TestFishId AS varchar(36)));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @GeneralImgId = @ImgB   -- @ImgB has the highest identity (inserted last), despite the earlier stamp
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_edit_fish_general fallback used newest fish_image by insert order (id=' + CAST(@ImgB AS varchar) + ')';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: fallback expected newest-by-identity id=' + ISNULL(CAST(@ImgB AS varchar), 'NULL')
            + ', got=' + ISNULL(CAST(@GeneralImgId AS varchar), 'NULL');

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;