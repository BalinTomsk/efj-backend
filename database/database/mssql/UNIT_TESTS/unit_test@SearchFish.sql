SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.SearchFishList.
  Uses real table dbo.fish. Each test wipes fish_rule/regulations/fish before inserting its
  own fixture row(s), so accumulation across tests sharing one transaction cannot inflate
  another test's exact-count assertion. Transaction is rolled back at end - database state
  restored.

  TEST  1 - find by single word name
  TEST  2 - find by double word name
  TEST  3 - find by single word name with a leading space
  TEST  4 - find by single word name with a trailing space
  TEST  5 - find by single word name surrounded by spaces
  TEST  6 - find by single word latin name
  TEST  7 - find by double word latin name
  TEST  8 - find by double word name with comma - full match
  TEST  9 - find by double word name with comma - alt word order match
  TEST 10 - find by double word name with comma - alt word order match (no comma in search)
  TEST 11 - find by three word name - full match
  TEST 12 - find by three word name - alt word order match
  TEST 13 - find by quadra word name
  TEST 14 - find by single synonym (alt_name)
  TEST 15 - find by double synonym, first alt_name entry
  TEST 16 - find by double synonym, second alt_name entry
  TEST 17 - find all Salmons (2 rows match)
  TEST 18 - find "fin tuna" (2 rows match)
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl1 TABLE (fish_name sysname); INSERT INTO @Tbl1 (fish_name) SELECT fish_name FROM dbo.SearchFishList('splike');
    DECLARE @R1a int = (SELECT COUNT(*) FROM @Tbl1), @R1b int = (SELECT COUNT(*) FROM @Tbl1 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1a = 1 AND @R1b = 1 PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by single word name';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R1a AS varchar) + ' match=' + CAST(@R1b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike fish', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl2 TABLE (fish_name sysname); INSERT INTO @Tbl2 (fish_name) SELECT fish_name FROM dbo.SearchFishList('splike fish');
    DECLARE @R2a int = (SELECT COUNT(*) FROM @Tbl2), @R2b int = (SELECT COUNT(*) FROM @Tbl2 WHERE fish_name = 'splike fish');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2a = 1 AND @R2b = 1 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by double word name';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R2a AS varchar) + ' match=' + CAST(@R2b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl3 TABLE (fish_name sysname); INSERT INTO @Tbl3 (fish_name) SELECT fish_name FROM dbo.SearchFishList(' splike');
    DECLARE @R3a int = (SELECT COUNT(*) FROM @Tbl3), @R3b int = (SELECT COUNT(*) FROM @Tbl3 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3a = 1 AND @R3b = 1 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found with leading space';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R3a AS varchar) + ' match=' + CAST(@R3b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl4 TABLE (fish_name sysname); INSERT INTO @Tbl4 (fish_name) SELECT fish_name FROM dbo.SearchFishList('splike ');
    DECLARE @R4a int = (SELECT COUNT(*) FROM @Tbl4), @R4b int = (SELECT COUNT(*) FROM @Tbl4 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4a = 1 AND @R4b = 1 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found with trailing space';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R4a AS varchar) + ' match=' + CAST(@R4b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl5 TABLE (fish_name sysname); INSERT INTO @Tbl5 (fish_name) SELECT fish_name FROM dbo.SearchFishList(' splike ');
    DECLARE @R5a int = (SELECT COUNT(*) FROM @Tbl5), @R5b int = (SELECT COUNT(*) FROM @Tbl5 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R5a = 1 AND @R5b = 1 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found surrounded by spaces';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R5a AS varchar) + ' match=' + CAST(@R5b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl6 TABLE (fish_name sysname); INSERT INTO @Tbl6 (fish_name) SELECT fish_name FROM dbo.SearchFishList('latin');
    DECLARE @R6a int = (SELECT COUNT(*) FROM @Tbl6), @R6b int = (SELECT COUNT(*) FROM @Tbl6 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R6a = 1 AND @R6b = 1 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by single word latin name';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R6a AS varchar) + ' match=' + CAST(@R6b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('splike', 'latin double', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl7 TABLE (fish_name sysname); INSERT INTO @Tbl7 (fish_name) SELECT fish_name FROM dbo.SearchFishList('latin double');
    DECLARE @R7a int = (SELECT COUNT(*) FROM @Tbl7), @R7b int = (SELECT COUNT(*) FROM @Tbl7 WHERE fish_name = 'splike');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R7a = 1 AND @R7b = 1 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by double word latin name';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R7a AS varchar) + ' match=' + CAST(@R7b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Sucker, Longnose', 'latin double', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl8 TABLE (fish_name sysname); INSERT INTO @Tbl8 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Sucker, Longnose');
    DECLARE @R8a int = (SELECT COUNT(*) FROM @Tbl8), @R8b int = (SELECT COUNT(*) FROM @Tbl8 WHERE fish_name = 'Sucker, Longnose');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R8a = 1 AND @R8b = 1 PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found comma name, full match';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R8a AS varchar) + ' match=' + CAST(@R8b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Sucker, Longnose', 'latin double', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl9 TABLE (fish_name sysname); INSERT INTO @Tbl9 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Longnose Sucker');
    DECLARE @R9a int = (SELECT COUNT(*) FROM @Tbl9), @R9b int = (SELECT COUNT(*) FROM @Tbl9 WHERE fish_name = 'Sucker, Longnose');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R9a = 1 AND @R9b = 1 PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found comma name, alt word order match';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R9a AS varchar) + ' match=' + CAST(@R9b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Sucker, Longnose', 'latin double', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl10 TABLE (fish_name sysname); INSERT INTO @Tbl10 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Sucker Longnose');
    DECLARE @R10a int = (SELECT COUNT(*) FROM @Tbl10), @R10b int = (SELECT COUNT(*) FROM @Tbl10 WHERE fish_name = 'Sucker, Longnose');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R10a = 1 AND @R10b = 1 PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found comma name, no-comma alt order match';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R10a AS varchar) + ' match=' + CAST(@R10b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Trout, Westslope Cutthroat', 'Oncorhynchus clarki lewisi', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl11 TABLE (fish_name sysname); INSERT INTO @Tbl11 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Trout, Westslope Cutthroat');
    DECLARE @R11a int = (SELECT COUNT(*) FROM @Tbl11), @R11b int = (SELECT COUNT(*) FROM @Tbl11 WHERE fish_name = 'Trout, Westslope Cutthroat');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R11a = 1 AND @R11b = 1 PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found three word name, full match';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R11a AS varchar) + ' match=' + CAST(@R11b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Trout, Westslope Cutthroat', 'Oncorhynchus clarki lewisi', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl12 TABLE (fish_name sysname); INSERT INTO @Tbl12 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Westslope Cutthroat Trout');
    DECLARE @R12a int = (SELECT COUNT(*) FROM @Tbl12), @R12b int = (SELECT COUNT(*) FROM @Tbl12 WHERE fish_name = 'Trout, Westslope Cutthroat');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R12a = 1 AND @R12b = 1 PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found three word name, alt word order match';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R12a AS varchar) + ' match=' + CAST(@R12b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic) VALUES ('Lamprey, Small black brook', 'latin double', '00000000-0000-0000-0000-000000000000', 0x00);
    DECLARE @Tbl13 TABLE (fish_name sysname); INSERT INTO @Tbl13 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Lamprey, Small black brook');
    DECLARE @R13a int = (SELECT COUNT(*) FROM @Tbl13), @R13b int = (SELECT COUNT(*) FROM @Tbl13 WHERE fish_name = 'Lamprey, Small black brook');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R13a = 1 AND @R13b = 1 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by quadra word name';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R13a AS varchar) + ' match=' + CAST(@R13b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Trout, Dolly Varden', 'Salvelinus malma', '00000000-0000-0000-0000-000000000000', 0x00, 'malma');
    DECLARE @Tbl14 TABLE (fish_name sysname); INSERT INTO @Tbl14 (fish_name) SELECT fish_name FROM dbo.SearchFishList('malma ');
    DECLARE @R14a int = (SELECT COUNT(*) FROM @Tbl14), @R14b int = (SELECT COUNT(*) FROM @Tbl14 WHERE fish_name = 'Trout, Dolly Varden');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R14a = 1 AND @R14b = 1 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by single synonym';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R14a AS varchar) + ' match=' + CAST(@R14b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Acadian redfish', 'Sebastes fasciatus', '00000000-0000-0000-0000-000000000000', 0x00, 'Atlantic redfish;ocean perch');
    DECLARE @Tbl15 TABLE (fish_name sysname); INSERT INTO @Tbl15 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Atlantic redfish ');
    DECLARE @R15a int = (SELECT COUNT(*) FROM @Tbl15), @R15b int = (SELECT COUNT(*) FROM @Tbl15 WHERE fish_name = 'Acadian redfish');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R15a = 1 AND @R15b = 1 PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by double synonym (Atlantic redfish)';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R15a AS varchar) + ' match=' + CAST(@R15b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Acadian redfish', 'Sebastes fasciatus', '00000000-0000-0000-0000-000000000000', 0x00, 'Atlantic redfish;ocean perch');
    DECLARE @Tbl16 TABLE (fish_name sysname); INSERT INTO @Tbl16 (fish_name) SELECT fish_name FROM dbo.SearchFishList('ocean perch');
    DECLARE @R16a int = (SELECT COUNT(*) FROM @Tbl16), @R16b int = (SELECT COUNT(*) FROM @Tbl16 WHERE fish_name = 'Acadian redfish');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R16a = 1 AND @R16b = 1 PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found by double synonym (ocean perch)';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: total=' + CAST(@R16a AS varchar) + ' match=' + CAST(@R16b AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Atlantic Salmon', 'Sebastes fasciatus', '00000000-0000-0000-0000-000000000000', 0x00, 'Salmo salar');
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Salmon, Coho', 'Oncorhynchus kisutch', '969E5641-010F-4E55-8E2C-00A04979F2CF', 0x00, 'Oncorhynchus kisutch');
    DECLARE @Tbl17 TABLE (fish_name sysname); INSERT INTO @Tbl17 (fish_name) SELECT fish_name FROM dbo.SearchFishList('Salmon');
    DECLARE @R17 int = (SELECT COUNT(*) FROM @Tbl17);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R17 = 2 PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found all 2 Salmons';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2, got ' + CAST(@R17 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM fish_rule; DELETE FROM regulations; DELETE FROM fish;
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Atlantic bluefin tuna', 'Thunnus thynnus', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 0x00, ' ');
    INSERT INTO fish (fish_name, fish_latin, family_Id, pic, alt_name) VALUES ('Albacore Tuna', 'Thunnus alalunga', '6B0D3CFE-7E3B-4109-A3A7-0A14C860850D', 0x00, ' ');
    DECLARE @Tbl18 TABLE (fish_name sysname); INSERT INTO @Tbl18 (fish_name) SELECT fish_name FROM dbo.SearchFishList('fin tuna');
    DECLARE @R18 int = (SELECT COUNT(*) FROM @Tbl18);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R18 = 2 PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: found "fin tuna" -> 2 matches';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 2, got ' + CAST(@R18 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
