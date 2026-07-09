SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for the fish_distribution_area column, exposed via two functions:
   - dbo.fn_read_fish_edit_list  (used by FishTracker.Editor.TFishEditor / FishEditor.aspx,
     TextBoxDistributionArea -- the admin edit form)
   - dbo.fn_edit_fish_general    (used by FishTracker.Editor.FishGeneral and
     FishTracker.Resources.wfFishViewer -- the public fish viewer)
  Uses real table dbo.fish. Transaction is rolled back at end -- database state fully restored.

  TEST 1 - fish_distribution_area round-trips through fn_read_fish_edit_list
  TEST 2 - NULL fish_distribution_area returns NULL, not an error
  TEST 3 - fish_distribution_area also round-trips through fn_edit_fish_general (public viewer)
*/
DECLARE @TestFamilyId uniqueidentifier = NEWID();
DECLARE @TestFishId1  uniqueidentifier = NEWID();
DECLARE @TestFishId2  uniqueidentifier = NEWID();
DECLARE @tStart       datetime2;
DECLARE @ElapsedMs    int;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dbo.fish_family (Family_id, Family_name, fid, created)
    VALUES (@TestFamilyId, N'__TEST_FAMILY__', -999, GETUTCDATE());

    -- ----------------------------------------------------------------
    -- TEST 1: distribution area text round-trips
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, fish_distribution_area, created, stamp)
    VALUES (@TestFishId1, N'__TEST_FISH_1__', N'Testus areatus', @TestFamilyId, N'North Atlantic; Gulf of Mexico', GETUTCDATE(), GETUTCDATE());

    DECLARE @Area1 nvarchar(500);
    SELECT @Area1 = distribution_area FROM dbo.fn_read_fish_edit_list() WHERE fish_id = @TestFishId1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Area1 = N'North Atlantic; Gulf of Mexico'
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_read_fish_edit_list returned the stored distribution area';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected ''North Atlantic; Gulf of Mexico'', got ' + ISNULL(@Area1, 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 2: NULL distribution area -> NULL, no error
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    INSERT INTO dbo.fish (fish_id, fish_name, fish_latin, family_Id, created, stamp)
    VALUES (@TestFishId2, N'__TEST_FISH_2__', N'Testus nullus', @TestFamilyId, GETUTCDATE(), GETUTCDATE());

    DECLARE @Area2 nvarchar(500);
    SELECT @Area2 = distribution_area FROM dbo.fn_read_fish_edit_list() WHERE fish_id = @TestFishId2;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Area2 IS NULL
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: unset distribution area returned NULL';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Area2;

    -- ----------------------------------------------------------------
    -- TEST 3: fn_edit_fish_general (public viewer) also returns the distribution area
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Area3 nvarchar(500);
    SELECT @Area3 = fish_distribution_area FROM dbo.fn_edit_fish_general(CAST(@TestFishId1 AS varchar(36)));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Area3 = N'North Atlantic; Gulf of Mexico'
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_edit_fish_general returned the stored distribution area';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected ''North Atlantic; Gulf of Mexico'', got ' + ISNULL(@Area3, 'NULL');

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
