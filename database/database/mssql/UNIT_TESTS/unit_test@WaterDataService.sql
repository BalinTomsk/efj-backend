SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for water data service functions'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'

PRINT 'Unit tests for sp_UpdateWaterData'

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestWDS1
DECLARE @test_name SYSNAME = 'TestWDS1 [sp_UpdateWaterData] inserts new water data row';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @mli varchar(64) = 'UT_WDS_01';
    DECLARE @stamp datetime2 = '2024-01-02T03:04:00';
    DECLARE @elevation float = 12.34;
    DECLARE @discharge float = 56.78;

    EXEC dbo.sp_UpdateWaterData @mli, @stamp, @elevation, @discharge;

    DECLARE @result_count int = (
        SELECT COUNT(*)
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    DECLARE @result_elevation float = (
        SELECT TOP 1 elevation
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    DECLARE @result_discharge float = (
        SELECT TOP 1 discharge
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    IF @result_count <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected exactly one row, actual ' + CAST(@result_count AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF ABS(ISNULL(@result_elevation, -999999.0) - 12.34) > 0.0001
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' elevation mismatch, actual ' + CAST(@result_elevation AS varchar(64));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF ABS(ISNULL(@result_discharge, -999999.0) - 56.78) > 0.0001
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' discharge mismatch, actual ' + CAST(@result_discharge AS varchar(64));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestWDS1
GO

----------------------------------------------------------------------------------------------------------
BEGIN TRAN TestWDS2
DECLARE @test_name SYSNAME = 'TestWDS2 [sp_UpdateWaterData] updates existing water data row';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @mli varchar(64) = 'UT_WDS_02';
    DECLARE @stamp datetime2 = '2024-01-02T05:06:00';

    INSERT INTO dbo.WaterData (mli, stamp, elevation, discharge)
    VALUES (@mli, CAST(@stamp AS smalldatetime), 1.11, 2.22);

    EXEC dbo.sp_UpdateWaterData @mli, @stamp, 9.99, 8.88;

    DECLARE @result_count int = (
        SELECT COUNT(*)
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    DECLARE @result_elevation float = (
        SELECT TOP 1 elevation
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    DECLARE @result_discharge float = (
        SELECT TOP 1 discharge
        FROM dbo.WaterData
        WHERE mli = @mli
          AND stamp = CAST(@stamp AS smalldatetime)
    );

    IF @result_count <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected single updated row, actual ' + CAST(@result_count AS varchar(32));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF ABS(ISNULL(@result_elevation, -999999.0) - 9.99) > 0.0001
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' elevation mismatch, actual ' + CAST(@result_elevation AS varchar(64));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF ABS(ISNULL(@result_discharge, -999999.0) - 8.88) > 0.0001
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' discharge mismatch, actual ' + CAST(@result_discharge AS varchar(64));
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestWDS2
GO
