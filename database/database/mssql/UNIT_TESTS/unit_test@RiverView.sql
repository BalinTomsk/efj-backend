SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for resource functions' 
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
-- database must be empty
----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
PRINT 'Unit tests for ffi' 

PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRV1
DECLARE @test_name SYSNAME = 'TestRV1 [fn_ViewTributary] no tributaries for river';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 2, N'River', 'ABCDE');

    -- 2. execute unit test 
	-- select * from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000', 0 )
    declare @result1 int = ( select count(*) from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000',1, 256  ));
    declare @result2 int = ( select count(*) from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000',0, 256  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 0 OR @result2 <> 0
	   RAISERROR ('FAILED: %s result must have single record %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestRV1 
GO
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRV2
DECLARE @test_name SYSNAME = 'TestRV2 [fn_ViewTributary] no tributaries for river';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('00000000-0000-0000-0000-000000000000', 1, N'Lake', 'ABCDE');

    -- 2. execute unit test 
	-- select * from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000', 0 )
    declare @result1 int = ( select count(*) from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000',1, 256  ));
    declare @result2 int = ( select count(*) from dbo.fn_ViewTributary('00000000-0000-0000-0000-000000000000',0, 256  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 0 OR @result2 <> 0
	   RAISERROR ('FAILED: %s result must have single record %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestRV2 
GO
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRV3
DECLARE @test_name SYSNAME = 'TestRV3 [fn_ViewTributary] set lake as mouth for river';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('20000000-0000-0000-0000-000000000000', 2,  N'River', 'ABCDE');
	insert into lake (lake_id, locType, lake_name, CGNDB) values ('10000000-1111-0000-0000-000000000000', 1,  N'Lake', 'FGHIJ');
    UPDATE Tributaries SET  [lake_id] = '10000000-1111-0000-0000-000000000000' 
       WHERE  lake_id = '20000000-0000-0000-0000-000000000000' AND  main_lake_id = '20000000-0000-0000-0000-000000000000' AND  side = 32
    exec sp_assign_border @lake_id='20000000-0000-0000-0000-000000000000'


    -- 2. execute unit test 
	-- select * from dbo.fn_ViewTributary('20000000-0000-0000-0000-000000000000', 1 )
	-- select * from dbo.fn_ViewTributary('10000000-1111-0000-0000-000000000000', 1 )
	-- select * from lake
	-- select * from Tributaries
    declare @result1 int = ( select count(*) from dbo.fn_ViewTributary('20000000-0000-0000-0000-000000000000',1, 256  ));
    declare @result2 int = ( select count(*) from dbo.fn_ViewTributary('10000000-1111-0000-0000-000000000000',1, 256  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 1 OR @result2 <> 1
	   RAISERROR ('FAILED: %s result must have single record %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestRV3 
GO
PRINT '-----------------------------------------------------------------------------------------------------------------------------' 
----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestRV4
DECLARE @test_name SYSNAME = 'TestRV4 [fn_ViewTributary] set lake as mouth for river';

BEGIN TRY  SET NOCOUNT ON;
    -- 1. prepare data for unit test
    insert into lake (lake_id, locType, lake_name, CGNDB) values ('20000000-0000-0000-0000-000000000000', 2,  N'River', 'ABCDE');
	insert into lake (lake_id, locType, lake_name, CGNDB) values ('10000000-1111-0000-0000-000000000000', 1,  N'Lake', 'FGHIJ');
    UPDATE Tributaries SET  [lake_id] = '10000000-1111-0000-0000-000000000000' 
       WHERE  lake_id = '20000000-0000-0000-0000-000000000000' AND  main_lake_id = '20000000-0000-0000-0000-000000000000' AND  side = 32
    exec sp_assign_border @lake_id='20000000-0000-0000-0000-000000000000'


    -- 2. execute unit test 
	-- select * from dbo.fn_ViewTributary('20000000-0000-0000-0000-000000000000', 1 )
	-- select * from dbo.fn_ViewTributary('10000000-1111-0000-0000-000000000000', 1 )
	-- select * from lake
	-- select * from Tributaries
    declare @result1 int = ( select count(*) from dbo.fn_ViewTributary('20000000-0000-0000-0000-000000000000',1, 256  ));
    declare @result2 int = ( select count(*) from dbo.fn_ViewTributary('10000000-1111-0000-0000-000000000000',1, 256  ));
 END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber,    ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
               @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine,         ERROR_MESSAGE() AS ErrorMessage;
END CATCH
    
	IF  @result1 <> 1 OR @result2 <> 1
	   RAISERROR ('FAILED: %s result must have single record %d ', 16, -1, @test_name, @result1 ) 
	ELSE
		print 'PASSED ' + @test_name
ROLLBACK TRAN TestRV4 
GO

 --  delete  from Tributaries ;delete  from lake;  
