SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for CloudProviderIp (fn_Ipv4ToBigint / IsCloudProviderIp / IsIpBlocked).
  Uses real tables dbo.CloudProviderIpRange (provider = 'UT_PROVIDER') and dbo.SessionHandler.
  Transaction is rolled back at end - database state restored.

  TEST  1 - fn_Ipv4ToBigint converts 1.2.3.4 to 16909060
  TEST  2 - fn_Ipv4ToBigint converts 255.255.255.255 to 4294967295
  TEST  3 - fn_Ipv4ToBigint returns NULL for invalid inputs
  TEST  4 - IsCloudProviderIp returns 1 for IP inside a seeded range
  TEST  5 - IsCloudProviderIp includes both range boundaries
  TEST  6 - IsCloudProviderIp returns 0 just outside the range
  TEST  7 - IsCloudProviderIp returns 0 in the gap between two disjoint ranges
  TEST  8 - IsCloudProviderIp returns 0 for NULL/invalid IP
  TEST  9 - IsIpBlocked returns 1 for a cloud-range IP
  TEST 10 - IsIpBlocked returns 1 for a SessionHandler-banned IP
  TEST 11 - IsIpBlocked returns 0 for an ordinary residential IP
  TEST 12 - disabled=1 range is excluded from IsCloudProviderIp; disabled=0 re-includes it
  TEST 13 - IsIpBlocked returns 0 when the only matching range is disabled
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;
DECLARE @Result    bigint;
DECLARE @Blocked   int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: converts a normal dotted-quad correctly
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_Ipv4ToBigint('1.2.3.4');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 16909060
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 1.2.3.4 converted to 16909060';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 16909060, got ' + ISNULL(CAST(@Result AS varchar), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 2: max address 255.255.255.255 converts to 4294967295
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    SET @Result = dbo.fn_Ipv4ToBigint('255.255.255.255');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Result = 4294967295
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 255.255.255.255 converted to 4294967295';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 4294967295, got ' + ISNULL(CAST(@Result AS varchar), 'NULL');

    -- ----------------------------------------------------------------
    -- TEST 3: invalid inputs (NULL, empty, IPv6, bad octet, wrong part count) return NULL
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @BadCnt int = 0;
    IF dbo.fn_Ipv4ToBigint(NULL)             IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('')               IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('::1')            IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('1.2.3')          IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('1.2.3.4.5')      IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('1.2.3.256')      IS NOT NULL SET @BadCnt = @BadCnt + 1;
    IF dbo.fn_Ipv4ToBigint('1.2.3.x')        IS NOT NULL SET @BadCnt = @BadCnt + 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @BadCnt = 0
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: invalid inputs all returned NULL';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: ' + CAST(@BadCnt AS varchar) + ' invalid input(s) did not return NULL';

    -- ----------------------------------------------------------------
    -- TEST 4: IsCloudProviderIp returns 1 for IP inside a seeded range
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24',    dbo.fn_Ipv4ToBigint('203.0.113.0'),    dbo.fn_Ipv4ToBigint('203.0.113.255'),    'unit-test'),
           ('UT_PROVIDER', '198.51.100.128/25', dbo.fn_Ipv4ToBigint('198.51.100.128'), dbo.fn_Ipv4ToBigint('198.51.100.255'), 'unit-test');
    SET @Blocked = dbo.IsCloudProviderIp('203.0.113.50');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 1
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 203.0.113.50 matched inside a seeded range';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@Blocked AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 5: boundary addresses (network and broadcast) are both inside the range
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');
    DECLARE @Net5 int = dbo.IsCloudProviderIp('203.0.113.0');
    DECLARE @Bcast5 int = dbo.IsCloudProviderIp('203.0.113.255');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Net5 = 1 AND @Bcast5 = 1
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: both range boundaries matched';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: network=' + CAST(@Net5 AS varchar) + ', broadcast=' + CAST(@Bcast5 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 6: IPs just outside the range (one below, one above) return 0
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');
    DECLARE @Below6 int = dbo.IsCloudProviderIp('203.0.112.255');
    DECLARE @Above6 int = dbo.IsCloudProviderIp('203.0.114.0');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Below6 = 0 AND @Above6 = 0
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: addresses just outside the range returned 0';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: below=' + CAST(@Below6 AS varchar) + ', above=' + CAST(@Above6 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 7: gap between two disjoint ranges is not matched
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '10.10.10.0/24', dbo.fn_Ipv4ToBigint('10.10.10.0'), dbo.fn_Ipv4ToBigint('10.10.10.255'), 'unit-test'),
           ('UT_PROVIDER', '10.10.30.0/24', dbo.fn_Ipv4ToBigint('10.10.30.0'), dbo.fn_Ipv4ToBigint('10.10.30.255'), 'unit-test');
    SET @Blocked = dbo.IsCloudProviderIp('10.10.20.5');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 0
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: gap address 10.10.20.5 returned 0';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@Blocked AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 8: NULL / invalid IP returns 0
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Null8 int = dbo.IsCloudProviderIp(NULL);
    DECLARE @Garbage8 int = dbo.IsCloudProviderIp('not-an-ip');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Null8 = 0 AND @Garbage8 = 0
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: NULL and garbage input both returned 0';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: null=' + CAST(@Null8 AS varchar) + ', garbage=' + CAST(@Garbage8 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 9: blocked because the IP is in a cloud range (not in SessionHandler at all)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '203.0.113.77';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');
    SET @Blocked = dbo.IsIpBlocked('203.0.113.77');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 1
        PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: cloud-range IP was blocked';
    ELSE
        PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@Blocked AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 10: blocked because the IP is manually banned in SessionHandler (no cloud range)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '192.168.40.10';
    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (NEWID(), 'UT_AGENT_BLK_10', 'UT_HOST_BLK_10', '/banned', 1, '192.168.40.10', 1);
    SET @Blocked = dbo.IsIpBlocked('192.168.40.10');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 1
        PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: manually-banned IP was blocked';
    ELSE
        PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@Blocked AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 11: not blocked when the IP is neither banned nor in any cloud range
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '24.85.120.42';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test');
    SET @Blocked = dbo.IsIpBlocked('24.85.120.42');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 0
        PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: ordinary residential IP was not blocked';
    ELSE
        PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@Blocked AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 12: a disabled range does NOT block; flipping it back on does
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source, disabled)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test', 1);
    DECLARE @Disabled12 int = dbo.IsCloudProviderIp('203.0.113.50');
    UPDATE dbo.CloudProviderIpRange SET disabled = 0 WHERE provider = 'UT_PROVIDER';
    DECLARE @Enabled12 int = dbo.IsCloudProviderIp('203.0.113.50');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Disabled12 = 0 AND @Enabled12 = 1
        PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: disabled range excluded, re-enabled range included';
    ELSE
        PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: disabled=' + CAST(@Disabled12 AS varchar) + ', enabled=' + CAST(@Enabled12 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 13: IsIpBlocked also honors the disabled override (no manual ban present)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.CloudProviderIpRange WHERE provider = 'UT_PROVIDER';
    DELETE FROM dbo.SessionHandler       WHERE ip4 = '203.0.113.99';
    INSERT INTO dbo.CloudProviderIpRange (provider, cidr, ipStart, ipEnd, source, disabled)
    VALUES ('UT_PROVIDER', '203.0.113.0/24', dbo.fn_Ipv4ToBigint('203.0.113.0'), dbo.fn_Ipv4ToBigint('203.0.113.255'), 'unit-test', 1);
    SET @Blocked = dbo.IsIpBlocked('203.0.113.99');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Blocked = 0
        PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: disabled-range IP not blocked';
    ELSE
        PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@Blocked AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
