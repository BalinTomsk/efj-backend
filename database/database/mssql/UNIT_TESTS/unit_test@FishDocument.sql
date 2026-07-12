SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for the fish PDF document feature:
   - dbo.sp_add_fish_document  (FishTracker.TFishEditor / FishEditor.aspx upload -- one per fish, replace)
   - dbo.sp_del_fish_document  (FishEditor.aspx remove)
   - dbo.fn_fish_document      (FishEditor.aspx / wfFishViewer.aspx link + HandlerImage.ashx?fishdoc= bytes)
  fish_document.fish_id FKs dbo.fish, so a fish fixture is created (and a fish_family parent for it).
  Transaction is rolled back at end -- database state fully restored.

  TEST 1 - sp_add_fish_document inserts the document; fn_fish_document returns label + bytes
  TEST 2 - re-uploading replaces the document (still exactly one row per fish)
  TEST 3 - sp_del_fish_document removes it; fn_fish_document then returns no rows
*/
DECLARE @TestFamilyId uniqueidentifier = NEWID();
DECLARE @TestFishId   uniqueidentifier = NEWID();
DECLARE @Pdf1         varbinary(max)   = 0x255044462D312E34;   -- "%PDF-1.4"
DECLARE @Pdf2         varbinary(max)   = 0x255044462D312E37AA; -- a different file
DECLARE @tStart       datetime2;
DECLARE @ElapsedMs    int;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
    VALUES (@TestFamilyId, N'__TEST_FAMILY_DOC__', -998, GETUTCDATE());

    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
    VALUES (@TestFishId, N'__TEST_FISH_DOC__', N'Testus documentus', @TestFamilyId, GETUTCDATE(), GETUTCDATE());

    -- ----------------------------------------------------------------
    -- TEST 1: add a document; fn_fish_document returns its label and bytes
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_fish_document @fish_id=@TestFishId, @image=@Pdf1, @label=N'guide.pdf';

    DECLARE @Cnt1 int, @Label1 nvarchar(256), @Bytes1 varbinary(max);
    SELECT @Cnt1 = COUNT(*) FROM dbo.fn_fish_document(@TestFishId);
    SELECT @Label1 = fish_document_label, @Bytes1 = fish_document_pic FROM dbo.fn_fish_document(@TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Cnt1 = 1 AND @Label1 = N'guide.pdf' AND @Bytes1 = @Pdf1
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: sp_add_fish_document stored the file; fn_fish_document returned label + bytes';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@Cnt1 AS varchar) + ', label=' + ISNULL(@Label1, 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 2: re-upload replaces (still one row; new bytes + label)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_add_fish_document @fish_id=@TestFishId, @image=@Pdf2, @label=N'revised.pdf';

    DECLARE @Cnt2 int, @Label2 nvarchar(256), @Bytes2 varbinary(max);
    SELECT @Cnt2 = COUNT(*) FROM dbo.fn_fish_document(@TestFishId);
    SELECT @Label2 = fish_document_label, @Bytes2 = fish_document_pic FROM dbo.fn_fish_document(@TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Cnt2 = 1 AND @Label2 = N'revised.pdf' AND @Bytes2 = @Pdf2
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: re-upload replaced the document (one row, new bytes)';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: count=' + CAST(@Cnt2 AS varchar) + ', label=' + ISNULL(@Label2, 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 3: delete removes it
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    EXEC dbo.sp_del_fish_document @fish_id=@TestFishId;

    DECLARE @Cnt3 int;
    SELECT @Cnt3 = COUNT(*) FROM dbo.fn_fish_document(@TestFishId);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Cnt3 = 0
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: sp_del_fish_document removed the document';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0 rows, got ' + CAST(@Cnt3 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
