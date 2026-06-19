SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for CloudProviderIp (fn_Ipv4ToBigint / IsCloudProviderIp / IsIpBlocked)'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.fn_Ipv4ToBigint
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 1: Converts a normal dotted-quad correctly
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestI2B1
DECLARE @test_name SYSNAME = 'TestI2B1 [fn_Ipv4ToBigint] converts 1.2.3.4 to 16909060';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @result BIGINT = dbo.fn_Ipv4ToBigint('1.2.3.4');

    IF @result <> 16909060          -- 1*2^24 + 2*2^16 + 3*2^8 + 4
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 16909060, actual ' + ISNULL(CAST(@result AS varchar(32)), 'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestI2B1
GO

-- TEST 2: Max address 255.255.255.255 converts to 4294967295
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestI2B2
DECLARE @test_name SYSNAME = 'TestI2B2 [fn_Ipv4ToBigint] converts 255.255.255.255 to 4294967295';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @result BIGINT = dbo.fn_Ipv4ToBigint('255.255.255.255');

    IF @result <> 4294967295
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 4294967295, actual ' + ISNULL(CAST(@result AS varchar(32)), 'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestI2B2
GO

-- TEST 3: Invalid inputs (NULL, empty, IPv6, bad octet, wrong part count) return NULL
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestI2B3
DECLARE @test_name SYSNAME = 'TestI2B3 [fn_Ipv4ToBigint] returns NULL for invalid inputs';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    IF dbo.fn_Ipv4ToBigint(NULL)            IS NOT NULL SET @fail_message = 'NULL input';
    ELSE IF dbo.fn_Ipv4ToBigint('')         IS NOT NULL SET @fail_message = 'empty input';
    ELSE IF dbo.fn_Ipv4ToBigint('::1')      IS NOT NULL SET @fail_message = 'IPv6 input';
    ELSE IF dbo.fn_Ipv4ToBigint('1.2.3')    IS NOT NULL SET @fail_message = '3-octet input';
    ELSE IF dbo.fn_Ipv4ToBigint('1.2.3.4.5')IS NOT NULL SET @fail_message = '5-octet input';
    ELSE IF dbo.fn_Ipv4ToBigint('1.2.3.256')IS NOT NULL SET @fail_message = 'octet > 255';
    ELSE IF dbo.fn_Ipv4ToBigint('1.2.3.x')  IS NOT NULL SET @fail_message = 'non-numeric octet';

    IF @fail_message IS NOT NULL
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected NULL for ' + @fail_message;
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestI2B3
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.IsCloudProviderIp
--   Seed a known range 203.0.113.0/24  ->  [203.0.113.0 .. 203.0.113.255]  =  [3405803776 .. 3405804031]
--   and a second disjoint range 198.51.100.128/25 -> [198.51.100.128 .. 198.51.100.255]
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 4: IP inside a seeded range returns 1
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestCPI4
DECLARE @test_name SYSNAME = 'TestCPI4 [IsCloudProviderIp] returns 1 for IP inside a range';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24',     dbo.fn_Ipv4ToBigint('203.0.113.0'),   dbo.fn_Ipv4ToBigint('203.0.113.255'),   'unit-test'),
           ('UT_PROVIDER', '198.51.100.128/25',  dbo.fn_Ipv4ToBigint('198.51.100.128'),dbo.fn_Ipv4ToBigint('198.51.100.255'),  'unit-test');

    IF dbo.IsCloudProviderIp('203.0.113.50') <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 1 for 203.0.113.50';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestCPI4
GO

-- TEST 5: Boundary addresses (network and broadcast) are both inside the range
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestCPI5
DECLARE @test_name SYSNAME = 'TestCPI5 [IsCloudProviderIp] includes both range boundaries';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');

    IF dbo.IsCloudProviderIp('203.0.113.0') <> 1
        SET @fail_message = 'network address 203.0.113.0 not matched';
    ELSE IF dbo.IsCloudProviderIp('203.0.113.255') <> 1
        SET @fail_message = 'broadcast address 203.0.113.255 not matched';

    IF @fail_message IS NOT NULL
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' ' + @fail_message;
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestCPI5
GO

-- TEST 6: IPs just outside the range (one below, one above) return 0
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestCPI6
DECLARE @test_name SYSNAME = 'TestCPI6 [IsCloudProviderIp] returns 0 just outside the range';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');

    IF dbo.IsCloudProviderIp('203.0.112.255') <> 0     -- one below ipStart
        SET @fail_message = '203.0.112.255 (below) should be 0';
    ELSE IF dbo.IsCloudProviderIp('203.0.114.0') <> 0  -- one above ipEnd
        SET @fail_message = '203.0.114.0 (above) should be 0';

    IF @fail_message IS NOT NULL
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' ' + @fail_message;
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestCPI6
GO

-- TEST 7: Gap between two disjoint ranges is not matched (TOP 1 ORDER BY ipStart DESC correctness)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestCPI7
DECLARE @test_name SYSNAME = 'TestCPI7 [IsCloudProviderIp] returns 0 in the gap between two ranges';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '10.10.10.0/24', dbo.fn_Ipv4ToBigint('10.10.10.0'), dbo.fn_Ipv4ToBigint('10.10.10.255'), 'unit-test'),
           ('UT_PROVIDER', '10.10.30.0/24', dbo.fn_Ipv4ToBigint('10.10.30.0'), dbo.fn_Ipv4ToBigint('10.10.30.255'), 'unit-test');

    -- 10.10.20.5 sits above the first range's ipStart but past its ipEnd, and below the second range.
    IF dbo.IsCloudProviderIp('10.10.20.5') <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 0 for 10.10.20.5 (in the gap)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestCPI7
GO

-- TEST 8: NULL / invalid IP returns 0
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestCPI8
DECLARE @test_name SYSNAME = 'TestCPI8 [IsCloudProviderIp] returns 0 for NULL/invalid IP';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    IF dbo.IsCloudProviderIp(NULL) <> 0
        SET @fail_message = 'NULL should be 0';
    ELSE IF dbo.IsCloudProviderIp('not-an-ip') <> 0
        SET @fail_message = 'garbage should be 0';

    IF @fail_message IS NOT NULL
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' ' + @fail_message;
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestCPI8
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.IsIpBlocked  (manual SessionHandler ban OR cloud-provider range)
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 9: Blocked because the IP is in a cloud range (not in SessionHandler at all)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestBLK9
DECLARE @test_name SYSNAME = 'TestBLK9 [IsIpBlocked] returns 1 for a cloud-range IP';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '203.0.113.77';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');

    IF dbo.IsIpBlocked('203.0.113.77') <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 1 (cloud range)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestBLK9
GO

-- TEST 10: Blocked because the IP is manually banned in SessionHandler (no cloud range)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestBLK10
DECLARE @test_name SYSNAME = 'TestBLK10 [IsIpBlocked] returns 1 for a SessionHandler-banned IP';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '192.168.40.10';

    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (NEWID(), 'UT_AGENT_BLK_10', 'UT_HOST_BLK_10', '/banned', 1, '192.168.40.10', 1);

    IF dbo.IsIpBlocked('192.168.40.10') <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 1 (manual ban)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestBLK10
GO

-- TEST 11: Not blocked when the IP is neither banned nor in any cloud range
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestBLK11
DECLARE @test_name SYSNAME = 'TestBLK11 [IsIpBlocked] returns 0 for an ordinary residential IP';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '24.85.120.42';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');

    IF dbo.IsIpBlocked('24.85.120.42') <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 0 (not banned, not cloud)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestBLK11
GO

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for the 'disabled' override column
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 12: A disabled range does NOT block; flipping it back on does
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestDIS12
DECLARE @test_name SYSNAME = 'TestDIS12 [IsCloudProviderIp] disabled=1 range is excluded, disabled=0 included';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source, disabled)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test', 1);

    IF dbo.IsCloudProviderIp('203.0.113.50') <> 0
        SET @fail_message = 'disabled=1 range should not match (expected 0)';
    ELSE
    BEGIN
        UPDATE dbo.CloudProviderIpRange SET disabled = 0 WHERE provider = 'UT_PROVIDER';
        IF dbo.IsCloudProviderIp('203.0.113.50') <> 1
            SET @fail_message = 're-enabled range should match (expected 1)';
    END

    IF @fail_message IS NOT NULL
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' ' + @fail_message;
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestDIS12
GO

-- TEST 13: IsIpBlocked also honors the disabled override (no manual ban present)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestDIS13
DECLARE @test_name SYSNAME = 'TestDIS13 [IsIpBlocked] returns 0 when the only matching range is disabled';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '203.0.113.99';

    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source, disabled)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test', 1);

    IF dbo.IsIpBlocked('203.0.113.99') <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected 0 (range disabled, not banned)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestDIS13
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
