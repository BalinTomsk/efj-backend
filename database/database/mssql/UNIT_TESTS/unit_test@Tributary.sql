SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for news' 
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
-- database may not be empty
----------------------------------------------------------------------------------------------------------

PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestT2
DECLARE @test_name SYSNAME = 'TestT2 [fn_river_view_news] find single news';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 2, N'River', 'ABCDE');
    insert into news ( news_title , news_author, lake_id) values ('test news', 'author', '00000000-0000-0000-0000-000000000000');
 
    -- 2. execute unit test 
    declare @result1 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',1  ));
    declare @result2 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',0  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 1 OR @result2 <> 0
	   RAISERROR ('FAILED: %s result must have single record %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestT2 
GO
 --  delete  from Tributaries ;delete  from lake; delete  from news; 
 PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestT1
DECLARE @test_name SYSNAME = 'TestT1 [fn_river_view_news] find no news';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 2, N'River', 'ABCDE');

 
    -- 2. execute unit test 
    declare @result1 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',1  ));
    declare @result2 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',0  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 0 OR @result2 <> 0
	   RAISERROR ('FAILED: %s result must be empty %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestT1 
GO
 PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestT3
DECLARE @test_name SYSNAME = 'TestT3 [fn_river_view_news] find 2 news';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 2, N'River', 'ABCDE');
    insert into news ( news_title , news_author, lake_id) values ('test news1', 'author', '00000000-0000-0000-0000-000000000000');
    insert into news ( news_title , news_author, lake_id) values ('test news2', 'author', '00000000-0000-0000-0000-000000000000');
 
    -- 2. execute unit test 
    declare @result1 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',1  ));
    declare @result2 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',0  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 1 OR @result2 <> 1
	   RAISERROR ('FAILED: %s result must have single record %d - %d', 16, -1, @test_name, @result1, @result2 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestT3 
GO
  PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestT4
DECLARE @test_name SYSNAME = 'TestT4 [fn_river_view_news] find 3 news';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 2, N'River', 'ABCDE');
    insert into news ( news_title , news_author, lake_id) values ('test news1', 'author', '00000000-0000-0000-0000-000000000000');
    insert into news ( news_title , news_author, lake_id) values ('test news2', 'author', '00000000-0000-0000-0000-000000000000');
    insert into news ( news_title , news_author, lake_id) values ('test news3', 'author', '00000000-0000-0000-0000-000000000000');
 
    -- 2. execute unit test 
    declare @result1 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',1  ));
    declare @result2 int = ( select count(*) from dbo.fn_river_view_news('00000000-0000-0000-0000-000000000000',0  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 2 OR @result2 <> 1
	   RAISERROR ('FAILED: %s result must have single record %d - %d', 16, -1, @test_name, @result1, @result2 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestT4 
GO
