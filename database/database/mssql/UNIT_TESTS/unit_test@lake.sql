SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_lake_edit / dbo.fn_xml_tributary.
  Uses real table dbo.lake, each row looked up by its own unique lake_name. Two tests in
  the original file (Width, french_name) reused a PRIOR test's lake_name by copy-paste,
  which was harmless when each test ran in its own isolated transaction but would collide
  once merged into one shared transaction (the name lookup would match 2 rows and the
  scalar assignment would error) - fixed here to use their own distinct names.
  Transaction is rolled back at end - database state restored.

  TEST  1 - lake name round-trips through fn_lake_edit
  TEST  2 - link round-trips
  TEST  3 - lake type (locType) round-trips
  TEST  4 - length round-trips
  TEST  5 - depth round-trips
  TEST  6 - width round-trips
  TEST  7 - basin round-trips
  TEST  8 - descript round-trips
  TEST  9 - drainage round-trips
  TEST 10 - discharge round-trips
  TEST 11 - watershield round-trips
  TEST 12 - fishing round-trips
  TEST 13 - volume round-trips
  TEST 14 - shoreline round-trips
  TEST 15 - surface round-trips
  TEST 16 - lake_road_access round-trips
  TEST 17 - CGNDB round-trips
  TEST 18 - native round-trips
  TEST 19 - french_name round-trips
  TEST 20 - alt_name round-trips
  TEST 21 - isolated round-trips
  TEST 22 - is_fishing_prohibited round-trips
  TEST 23 - fn_xml_tributary returns no tributary node for a lake with none
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @Doc       xml;
DECLARE @Rst       nvarchar(max);
DECLARE @LakeId    uniqueidentifier;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name) VALUES (999, N'TestLakeName');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeName');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node/text())[1]', 'varchar(100)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'TestLakeName' PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake name round-trips';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, link) VALUES (999, N'TestLakeLink', N'www.link');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeLink');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="link"]/text())[1]', 'nvarchar(255)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'www.link' PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: link round-trips';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name) VALUES (1, N'TestLakeType');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeType');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstType int = (SELECT T.C.value('@locType', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstType = 1 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake type round-trips';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstType AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, length) VALUES (1, N'TestLakeLength', 666);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeLength');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstLength int = (SELECT T.C.value('@length', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstLength = 666 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: length round-trips';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstLength AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, depth) VALUES (1, N'TestLakeDepth', 777);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeDepth');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstDepth int = (SELECT T.C.value('@depth', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstDepth = 777 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: depth round-trips';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstDepth AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, width) VALUES (1, N'TestLakeWidth', 878);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeWidth');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstWidth int = (SELECT T.C.value('@width', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstWidth = 878 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: width round-trips';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstWidth AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, basin) VALUES (1, N'TestLakeBasin', 'Basin');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeBasin');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstBasin varchar(64) = (SELECT T.C.value('@basin', 'varchar(64)') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstBasin = 'Basin' PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: basin round-trips';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@RstBasin, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, descript) VALUES (999, N'TestLakdescript', N'descript');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakdescript');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="descript"]/text())[1]', 'nvarchar(255)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'descript' PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: descript round-trips';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, drainage) VALUES (999, N'TestLakdedrainage', N'drainage');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakdedrainage');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="drainage"]/text())[1]', 'nvarchar(128)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'drainage' PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: drainage round-trips';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, discharge) VALUES (999, N'TestLakdeDischarge', N'discharge');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakdeDischarge');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="discharge"]/text())[1]', 'nvarchar(255)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'discharge' PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: discharge round-trips';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, watershield) VALUES (999, N'TestLakewatershield', N'watershield');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakewatershield');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="watershield"]/text())[1]', 'nvarchar(255)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'watershield' PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: watershield round-trips';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, fishing) VALUES (999, N'TestLake_fishing', N'fishing');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLake_fishing');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="fishing"]/text())[1]', 'nvarchar(max)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'fishing' PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fishing round-trips';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, volume) VALUES (1, N'TestLakeVolume', 17);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeVolume');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstVolume float = (SELECT T.C.value('@volume', 'float') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstVolume = 17 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: volume round-trips';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstVolume AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, shoreline) VALUES (1, N'TestLakeShoreline', 666);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeShoreline');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstShoreline int = (SELECT T.C.value('@shoreline', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstShoreline = 666 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: shoreline round-trips';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstShoreline AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, surface) VALUES (1, N'TestLakeSurface', 666);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeSurface');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstSurface int = (SELECT T.C.value('@surface', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstSurface = 666 PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: surface round-trips';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstSurface AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, lake_road_access) VALUES (999, N'TestLake_road_access', N'lake_road_access');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLake_road_access');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="lake_road_access"]/text())[1]', 'nvarchar(max)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'lake_road_access' PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: lake_road_access round-trips';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, CGNDB) VALUES (1, N'TestLakeCGNDB', 'CGNDB');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeCGNDB');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstCgndb char(5) = (SELECT T.C.value('@CGNDB', 'char(5)') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstCgndb = 'CGNDB' PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: CGNDB round-trips';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@RstCgndb, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, native) VALUES (999, N'TestLakeNative', N'native');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeNative');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="native"]/text())[1]', 'nvarchar(64)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'native' PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: native round-trips';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, french_name) VALUES (999, N'TestLake_french_name', N'french_name');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLake_french_name');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="french_name"]/text())[1]', 'nvarchar(128)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'french_name' PRINT 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: french_name round-trips';
    ELSE PRINT 'TEST 19 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, alt_name) VALUES (999, N'TestLake_alt_name', N'alt_name');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLake_alt_name');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    SET @Rst = @Doc.value('(/root/node[@name="alt_name"]/text())[1]', 'nvarchar(64)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst = N'alt_name' PRINT 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: alt_name round-trips';
    ELSE PRINT 'TEST 20 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(@Rst, 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, isolated) VALUES (1, N'TestLakeIsolated', 1);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeIsolated');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstIsolated int = (SELECT T.C.value('@isolated', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstIsolated = 1 PRINT 'TEST 21 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: isolated round-trips';
    ELSE PRINT 'TEST 21 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstIsolated AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name, is_fishing_prohibited) VALUES (1, N'TestLakeProhibited', 1);
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestLakeProhibited');
    SET @Doc = dbo.fn_lake_edit(@LakeId);
    DECLARE @RstProhibited int = (SELECT T.C.value('@is_fishing_prohibited', 'int') FROM @Doc.nodes('/root/lake') T(C));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @RstProhibited = 1 PRINT 'TEST 22 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: is_fishing_prohibited round-trips';
    ELSE PRINT 'TEST 22 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: got ' + ISNULL(CAST(@RstProhibited AS varchar), 'NULL');

    SET @tStart = SYSUTCDATETIME();
    INSERT INTO lake (locType, lake_name) VALUES (1, N'TestXmlTributary');
    SET @LakeId = (SELECT lake_id FROM lake WHERE lake_name = N'TestXmlTributary');
    SET @Doc = dbo.fn_xml_tributary(@LakeId, 0);
    SET @Rst = @Doc.value('(/root/node/text())[1]', 'nvarchar(64)');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Rst IS NULL PRINT 'TEST 23 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: fn_xml_tributary returns no tributary node';
    ELSE PRINT 'TEST 23 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected NULL, got ' + @Rst;

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
