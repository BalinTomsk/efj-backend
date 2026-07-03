SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_river_view_news.
  Uses real tables dbo.lake / dbo.news. Transaction is rolled back at end -
  database state restored.

  TEST 1 - find single news
  TEST 2 - find no news
  TEST 3 - find 2 news
  TEST 4 - find 3 news
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: find single news
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake1 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake1, 2, N'River', 'UTTB1');
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news', 'author', @Lake1);
    DECLARE @R1a int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake1, 1));
    DECLARE @R1b int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake1, 0));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R1a = 1 AND @R1b = 0
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: single news item found';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: flag1=' + CAST(@R1a AS varchar) + ' flag0=' + CAST(@R1b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 2: find no news
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake2 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake2, 2, N'River', 'UTTB2');
    DECLARE @R2a int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake2, 1));
    DECLARE @R2b int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake2, 0));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R2a = 0 AND @R2b = 0
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: no news items found';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: flag1=' + CAST(@R2a AS varchar) + ' flag0=' + CAST(@R2b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: find 2 news
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake3 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake3, 2, N'River', 'UTTB3');
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news1 T3', 'author', @Lake3);
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news2 T3', 'author', @Lake3);
    DECLARE @R3a int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake3, 1));
    DECLARE @R3b int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake3, 0));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R3a = 1 AND @R3b = 1
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: two news items found';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: flag1=' + CAST(@R3a AS varchar) + ' flag0=' + CAST(@R3b AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 4: find 3 news
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Lake4 uniqueidentifier = NEWID();
    INSERT INTO lake (lake_id, locType, lake_name, CGNDB) VALUES (@Lake4, 2, N'River', 'UTTB4');
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news1 T4', 'author', @Lake4);
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news2 T4', 'author', @Lake4);
    INSERT INTO news (news_title, news_author, lake_id) VALUES ('test news3 T4', 'author', @Lake4);
    DECLARE @R4a int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake4, 1));
    DECLARE @R4b int = (SELECT COUNT(*) FROM dbo.fn_river_view_news(@Lake4, 0));
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @R4a = 2 AND @R4b = 1
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: three news items -> flag1=2, flag0=1';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: flag1=' + CAST(@R4a AS varchar) + ' flag0=' + CAST(@R4b AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
