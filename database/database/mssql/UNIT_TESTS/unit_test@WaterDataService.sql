SET NOCOUNT ON;  -- FIX: suppress "(X rows affected)" messages

PRINT 'Unit tests for water data service functions';
PRINT '-----------------------------------------------------------------------------------------------------------------------------';
PRINT 'Unit tests for sp_UpdateWaterData';

-- ============================================================
-- TestWDS1: inserts new water data row
-- ============================================================
BEGIN
    DECLARE @mli1   varchar(64)   = 'TEST_WDS1_MLI';
    DECLARE @stamp1 smalldatetime = DATEADD(DAY, -1, GETDATE());
    DECLARE @elev1  float         = 100.0;
    DECLARE @disch1 float         = 5.0;

    DELETE FROM dbo.WaterData WHERE mli = @mli1;

    EXEC dbo.sp_UpdateWaterData @mli = @mli1, @stamp = @stamp1, @elevation = @elev1, @discharge = @disch1;

    DECLARE @count1 int = (SELECT COUNT(1) FROM dbo.WaterData WHERE mli = @mli1);

    IF @count1 = 1
        PRINT 'PASSED TestWDS1 [sp_UpdateWaterData] inserts new water data row'
    ELSE
        THROW 50000, 'FAILED: TestWDS1 [sp_UpdateWaterData] inserts new water data row expected exactly one row, actual 0', 1;

    DELETE FROM dbo.WaterData WHERE mli = @mli1;
END;

-- ============================================================
-- TestWDS2: updates existing water data row
-- ============================================================
BEGIN
    DECLARE @mli2    varchar(64)   = 'TEST_WDS2_MLI';
    DECLARE @stamp2  smalldatetime = DATEADD(DAY, -2, GETDATE());
    DECLARE @elev2a  float         = 50.0;
    DECLARE @disch2a float         = 2.0;
    DECLARE @elev2b  float         = 75.0;
    DECLARE @disch2b float         = 4.0;

    DELETE FROM dbo.WaterData WHERE mli = @mli2;

    EXEC dbo.sp_UpdateWaterData @mli = @mli2, @stamp = @stamp2, @elevation = @elev2a, @discharge = @disch2a;
    EXEC dbo.sp_UpdateWaterData @mli = @mli2, @stamp = @stamp2, @elevation = @elev2b, @discharge = @disch2b;

    DECLARE @updElev2 float = (SELECT elevation FROM dbo.WaterData WHERE mli = @mli2 AND stamp = @stamp2);

    IF @updElev2 = @elev2b
        PRINT 'PASSED TestWDS2 [sp_UpdateWaterData] updates existing water data row'
    ELSE
        THROW 50000, 'FAILED: TestWDS2 [sp_UpdateWaterData] updates existing water data row', 1;

    DELETE FROM dbo.WaterData WHERE mli = @mli2;
END;

-- ============================================================
-- TestWDS3: deletes records older than 15 days after successful insert
-- ============================================================
BEGIN
    DECLARE @mli3        varchar(64)   = 'TEST_WDS3_MLI';
    DECLARE @oldStamp    smalldatetime = DATEADD(DAY, -16, GETDATE());
    DECLARE @recentStamp smalldatetime = DATEADD(DAY,  -5, GETDATE());
    DECLARE @newStamp    smalldatetime = GETDATE();

    DELETE FROM dbo.WaterData WHERE mli = @mli3;

    INSERT INTO dbo.WaterData (mli, stamp, elevation, discharge)
    VALUES (@mli3, @oldStamp,    10.0, 1.0),
           (@mli3, @recentStamp, 20.0, 2.0);

    EXEC dbo.sp_UpdateWaterData @mli = @mli3, @stamp = @newStamp, @elevation = 30.0, @discharge = 3.0;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterData WHERE mli = @mli3 AND stamp < DATEADD(DAY, -15, GETDATE()))
        PRINT 'PASSED TestWDS3 [sp_UpdateWaterData] deletes records older than 15 days after insert'
    ELSE
        THROW 50000, 'FAILED: TestWDS3 [sp_UpdateWaterData] deletes records older than 15 days after insert', 1;

    IF EXISTS (SELECT 1 FROM dbo.WaterData WHERE mli = @mli3 AND stamp >= DATEADD(DAY, -15, GETDATE()) AND stamp < DATEADD(DAY, -4, GETDATE()))
        PRINT 'PASSED TestWDS3b [sp_UpdateWaterData] retains records within 15 days'
    ELSE
        THROW 50000, 'FAILED: TestWDS3b [sp_UpdateWaterData] retains records within 15 days', 1;

    DELETE FROM dbo.WaterData WHERE mli = @mli3;
END;
