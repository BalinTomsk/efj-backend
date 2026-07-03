SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.fn_SessionHandlerTodayConsumedPages, dbo.spPersistIpBan,
  dbo.spRegisterPageHit, dbo.IsIpBanned.
  Uses real table dbo.SessionHandler. Each test scrubs its own host/ip4 fixture rows
  before running, so merging into one shared transaction does not create cross-test
  interference. Transaction is rolled back at end - database state restored.

  TEST  1 - fn_SessionHandlerTodayConsumedPages returns 0 when no records exist
  TEST  2 - fn_SessionHandlerTodayConsumedPages sums a single IPv4 record
  TEST  3 - fn_SessionHandlerTodayConsumedPages excludes a different host
  TEST  4 - spPersistIpBan inserts a new record when ip4 does not exist
  TEST  5 - spPersistIpBan updates the existing record when matching ip4 exists
  TEST  6 - spPersistIpBan inserts when ip4 parameter is an empty string
  TEST  7 - spPersistIpBan insert stores @baned value when no match exists
  TEST  8 - spPersistIpBan update always sets baned = 1
  TEST  9 - spPersistIpBan updates existing row by ip4
  TEST 10 - spRegisterPageHit inserts new record when today's ip4 does not exist
  TEST 11 - spRegisterPageHit updates today's row and increments counterPage
  TEST 12 - spRegisterPageHit inserts a today row when only a yesterday row exists
  TEST 13 - spRegisterPageHit inserts when ip4 parameter is an empty string
  TEST 14 - spRegisterPageHit insert stores @baned value when no match exists
  TEST 15 - spRegisterPageHit update always sets baned = 0
  TEST 16 - IsIpBanned returns 0 when ip4 is NULL
  TEST 17 - IsIpBanned returns 0 when ip4 is empty string
  TEST 18 - IsIpBanned returns 0 when no matching ip4 exists
  TEST 19 - IsIpBanned returns 0 when matching ip4 exists but baned = 0
  TEST 20 - IsIpBanned returns 1 when matching ip4 exists and baned = 1
  TEST 21 - IsIpBanned returns 0 for a different banned ip4
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_01';
    DECLARE @T1 int = dbo.fn_SessionHandlerTodayConsumedPages('192.168.1.1', 'UT_HOST_01');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T1 = 0 PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 when no records exist';
    ELSE PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T1 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_02';
    INSERT INTO dbo.SessionHandler (startSess, host, ip4, counterPage, baned, userAgent)
    VALUES (GETUTCDATE(), 'UT_HOST_02', '10.0.0.1', 15, 0, 'UT_HOST_02');
    DECLARE @T2 int = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.1', 'UT_HOST_02');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T2 = 15 PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: sums single IPv4 record';
    ELSE PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 15, got ' + CAST(@T2 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_07A', 'UT_HOST_07B');
    INSERT INTO dbo.SessionHandler (startSess, host, ip4, counterPage, baned, userAgent)
    VALUES (GETUTCDATE(), 'UT_HOST_07A', '10.0.0.7', 10, 0, 'UT_HOST_07'),
           (GETUTCDATE(), 'UT_HOST_07B', '10.0.0.8', 30, 0, 'UT_HOST_08');
    DECLARE @T3 int = dbo.fn_SessionHandlerTodayConsumedPages('10.0.0.7', 'UT_HOST_07A');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T3 = 10 PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: excludes a different host';
    ELSE PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 10, got ' + CAST(@T3 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_PIB_01';
    DECLARE @Id4 uniqueidentifier = NEWID();
    EXEC dbo.spPersistIpBan @counterPage=5, @agent=N'UT_AGENT_01', @host=N'UT_HOST_PIB_01', @ip4='192.168.10.1', @startPage=N'/unit-test-start', @baned=1, @id=@Id4;
    DECLARE @T4 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id4 AND ip4 = '192.168.10.1' AND userAgent = N'UT_AGENT_01' AND host = 'UT_HOST_PIB_01' AND startPage = '/unit-test-start' AND baned = 1 AND counterPage = 5) SET @T4 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T4 = 1 PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: inserts new record when ip4 does not exist';
    ELSE PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted row was not found';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_02_OLD', 'UT_HOST_PIB_02_NEW');
    DECLARE @Id5 uniqueidentifier = NEWID(), @NewId5 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@Id5, GETDATE(), N'OLD_AGENT', 'UT_HOST_PIB_02_OLD', '/old', 0, '192.168.10.2', 1);
    EXEC dbo.spPersistIpBan @counterPage=9, @agent=N'NEW_AGENT', @host=N'UT_HOST_PIB_02_NEW', @ip4='192.168.10.2', @startPage=N'/new-start-page', @baned=0, @id=@NewId5;
    DECLARE @T5 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id5 AND ip4 = '192.168.10.2' AND userAgent = N'NEW_AGENT' AND host = 'UT_HOST_PIB_02_NEW' AND baned = 1 AND counterPage = 9)
       AND NOT EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId5) SET @T5 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T5 = 1 PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: updates existing record when matching ip4 exists';
    ELSE PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected existing row to be updated (not inserted)';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_03_OLD', 'UT_HOST_PIB_03_NEW');
    DECLARE @OldId6 uniqueidentifier = NEWID(), @NewId6 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@OldId6, GETDATE(), N'OLD_AGENT', 'UT_HOST_PIB_03_OLD', '/old', 0, '', 1);
    EXEC dbo.spPersistIpBan @counterPage=4, @agent=N'NEW_AGENT_EMPTY_IP', @host=N'UT_HOST_PIB_03_NEW', @ip4='', @startPage=N'/empty-ip-start', @baned=1, @id=@NewId6;
    DECLARE @T6 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId6 AND ip4 = '' AND userAgent = N'NEW_AGENT_EMPTY_IP' AND host = 'UT_HOST_PIB_03_NEW' AND startPage = '/empty-ip-start' AND baned = 1 AND counterPage = 4)
       AND EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @OldId6 AND userAgent = N'OLD_AGENT' AND host = 'UT_HOST_PIB_03_OLD' AND counterPage = 1 AND baned = 0) SET @T6 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T6 = 1 PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: inserts when ip4 parameter is empty string';
    ELSE PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty-ip insert/old-row-unchanged assertion failed';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host = 'UT_HOST_PIB_04';
    DECLARE @Id7 uniqueidentifier = NEWID();
    EXEC dbo.spPersistIpBan @counterPage=2, @agent=N'UT_AGENT_04', @host=N'UT_HOST_PIB_04', @ip4='192.168.10.4', @startPage=N'/not-banned', @baned=0, @id=@Id7;
    DECLARE @T7 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id7 AND ip4 = '192.168.10.4' AND baned = 0 AND counterPage = 2) SET @T7 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T7 = 1 PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stores @baned value when no match exists';
    ELSE PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted row with baned = 0';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_PIB_05_OLD', 'UT_HOST_PIB_05_NEW');
    DECLARE @Id8 uniqueidentifier = NEWID(), @NewId8 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@Id8, GETDATE(), N'OLD_AGENT_05', 'UT_HOST_PIB_05_OLD', '/old', 0, '192.168.10.5', 1);
    EXEC dbo.spPersistIpBan @counterPage=8, @agent=N'NEW_AGENT_05', @host=N'UT_HOST_PIB_05_NEW', @ip4='192.168.10.5', @startPage=N'/ignored-on-update', @baned=0, @id=@NewId8;
    DECLARE @T8 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id8 AND baned = 1 AND counterPage = 8 AND userAgent = N'NEW_AGENT_05' AND host = 'UT_HOST_PIB_05_NEW') SET @T8 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T8 = 1 PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: update always sets baned = 1';
    ELSE PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected update to set baned = 1';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.10.6';
    DECLARE @ExistingId9 uniqueidentifier = NEWID(), @NewId9 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@ExistingId9, 'OLD_AGENT', 'UT_HOST_OLD', '/old', 0, '192.168.10.6', 1);
    EXEC dbo.spPersistIpBan @counterPage=12, @agent=N'NEW_AGENT_06', @host=N'UT_HOST_NEW', @ip4='192.168.10.6', @startPage=N'/ignored', @baned=0, @id=@NewId9;
    DECLARE @T9 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @ExistingId9 AND ip4 = '192.168.10.6' AND userAgent = 'NEW_AGENT_06' AND host = 'UT_HOST_NEW' AND baned = 1 AND counterPage = 12)
       AND NOT EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId9) SET @T9 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T9 = 1 PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: updates existing row by ip4';
    ELSE PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected existing row to be updated (not inserted)';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.1';
    DECLARE @Id10 uniqueidentifier = NEWID();
    EXEC dbo.spRegisterPageHit @counterPage=3, @agent=N'UT_AGENT_RPH_01', @host=N'UT_HOST_RPH_01', @ip4='192.168.20.1', @startPage=N'/rph-start-01', @baned=1, @id=@Id10;
    DECLARE @T10 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id10 AND ip4 = '192.168.20.1' AND userAgent = 'UT_AGENT_RPH_01' AND host = 'UT_HOST_RPH_01' AND startPage = '/rph-start-01' AND baned = 1 AND counterPage = 3 AND activityDate = CAST(GETUTCDATE() AS date)) SET @T10 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T10 = 1 PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: inserts new record when ip4 does not exist today';
    ELSE PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted row was not found';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.2';
    DECLARE @ExistingId11 uniqueidentifier = NEWID(), @NewId11 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@ExistingId11, GETUTCDATE(), 'OLD_AGENT_RPH_02', 'UT_HOST_RPH_02_OLD', '/old-page', 1, '192.168.20.2', 7);
    EXEC dbo.spRegisterPageHit @counterPage=5, @agent=N'NEW_AGENT_RPH_02', @host=N'UT_HOST_RPH_02_NEW', @ip4='192.168.20.2', @startPage=N'/new-page', @baned=1, @id=@NewId11;
    DECLARE @T11 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @ExistingId11 AND ip4 = '192.168.20.2' AND userAgent = 'NEW_AGENT_RPH_02' AND host = 'UT_HOST_RPH_02_NEW' AND startPage = '/new-page' AND baned = 0 AND counterPage = 12 AND activityDate = CAST(GETUTCDATE() AS date))
       AND NOT EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId11) SET @T11 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T11 = 1 PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: updates today row and increments counterPage to 12';
    ELSE PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected today row updated, not a new insert';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.3';
    DECLARE @OldId12 uniqueidentifier = NEWID(), @NewId12 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@OldId12, DATEADD(day, -1, GETUTCDATE()), 'OLD_AGENT_RPH_03', 'UT_HOST_RPH_03_OLD', '/old-page', 1, '192.168.20.3', 10);
    EXEC dbo.spRegisterPageHit @counterPage=4, @agent=N'NEW_AGENT_RPH_03', @host=N'UT_HOST_RPH_03_NEW', @ip4='192.168.20.3', @startPage=N'/today-page', @baned=0, @id=@NewId12;
    DECLARE @T12 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId12 AND ip4 = '192.168.20.3' AND userAgent = 'NEW_AGENT_RPH_03' AND host = 'UT_HOST_RPH_03_NEW' AND startPage = '/today-page' AND baned = 0 AND counterPage = 4 AND activityDate = CAST(GETUTCDATE() AS date))
       AND EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @OldId12 AND activityDate = CAST(DATEADD(day, -1, GETUTCDATE()) AS date) AND counterPage = 10 AND baned = 1 AND userAgent = 'OLD_AGENT_RPH_03') SET @T12 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T12 = 1 PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: inserts today row when only yesterday row exists';
    ELSE PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: today-insert/yesterday-unchanged assertion failed';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE host IN ('UT_HOST_RPH_04_OLD', 'UT_HOST_RPH_04_NEW');
    DECLARE @OldId13 uniqueidentifier = NEWID(), @NewId13 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@OldId13, GETUTCDATE(), 'OLD_AGENT_RPH_04', 'UT_HOST_RPH_04_OLD', '/old-empty-ip', 1, '', 6);
    EXEC dbo.spRegisterPageHit @counterPage=2, @agent=N'NEW_AGENT_RPH_04', @host=N'UT_HOST_RPH_04_NEW', @ip4='', @startPage=N'/new-empty-ip', @baned=0, @id=@NewId13;
    DECLARE @T13 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @NewId13 AND ip4 = '' AND userAgent = 'NEW_AGENT_RPH_04' AND host = 'UT_HOST_RPH_04_NEW' AND startPage = '/new-empty-ip' AND baned = 0 AND counterPage = 2)
       AND EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @OldId13 AND userAgent = 'OLD_AGENT_RPH_04' AND host = 'UT_HOST_RPH_04_OLD' AND startPage = '/old-empty-ip' AND baned = 1 AND counterPage = 6) SET @T13 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T13 = 1 PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: inserts when ip4 parameter is empty string';
    ELSE PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty-ip insert/old-row-unchanged assertion failed';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.5';
    DECLARE @Id14 uniqueidentifier = NEWID();
    EXEC dbo.spRegisterPageHit @counterPage=1, @agent=N'UT_AGENT_RPH_05', @host=N'UT_HOST_RPH_05', @ip4='192.168.20.5', @startPage=N'/insert-baned-true', @baned=1, @id=@Id14;
    DECLARE @T14 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @Id14 AND ip4 = '192.168.20.5' AND baned = 1 AND counterPage = 1 AND startPage = '/insert-baned-true') SET @T14 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T14 = 1 PRINT 'TEST 14 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: insert stores @baned value when no match exists';
    ELSE PRINT 'TEST 14 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected inserted row with baned = 1';

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.20.6';
    DECLARE @ExistingId15 uniqueidentifier = NEWID(), @NewId15 uniqueidentifier = NEWID();
    INSERT INTO dbo.SessionHandler (id, startSess, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (@ExistingId15, GETUTCDATE(), 'OLD_AGENT_RPH_06', 'UT_HOST_RPH_06_OLD', '/old', 1, '192.168.20.6', 3);
    EXEC dbo.spRegisterPageHit @counterPage=2, @agent=N'NEW_AGENT_RPH_06', @host=N'UT_HOST_RPH_06_NEW', @ip4='192.168.20.6', @startPage=N'/new', @baned=1, @id=@NewId15;
    DECLARE @T15 bit = 0;
    IF EXISTS (SELECT 1 FROM dbo.SessionHandler WHERE id = @ExistingId15 AND baned = 0 AND counterPage = 5 AND userAgent = 'NEW_AGENT_RPH_06' AND host = 'UT_HOST_RPH_06_NEW' AND startPage = '/new') SET @T15 = 1;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T15 = 1 PRINT 'TEST 15 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: update always sets baned = 0 and increments counterPage';
    ELSE PRINT 'TEST 15 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected update to set baned = 0 and counterPage = 5';

    SET @tStart = SYSUTCDATETIME();
    DECLARE @T16 bit = dbo.IsIpBanned(NULL);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T16 = 0 PRINT 'TEST 16 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 when ip4 is NULL';
    ELSE PRINT 'TEST 16 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T16 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DECLARE @T17 bit = dbo.IsIpBanned('');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T17 = 0 PRINT 'TEST 17 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 when ip4 is empty string';
    ELSE PRINT 'TEST 17 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T17 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.30.3';
    DECLARE @T18 bit = dbo.IsIpBanned('192.168.30.3');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T18 = 0 PRINT 'TEST 18 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 when no matching ip4 exists';
    ELSE PRINT 'TEST 18 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T18 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.30.4';
    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (NEWID(), 'UT_AGENT_IIB_04', 'UT_HOST_IIB_04', '/not-banned', 0, '192.168.30.4', 1);
    DECLARE @T19 bit = dbo.IsIpBanned('192.168.30.4');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T19 = 0 PRINT 'TEST 19 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 when matching ip4 exists but baned = 0';
    ELSE PRINT 'TEST 19 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T19 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 = '192.168.30.5';
    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (NEWID(), 'UT_AGENT_IIB_05', 'UT_HOST_IIB_05', '/banned', 1, '192.168.30.5', 1);
    DECLARE @T20 bit = dbo.IsIpBanned('192.168.30.5');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T20 = 1 PRINT 'TEST 20 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 1 when matching ip4 exists and baned = 1';
    ELSE PRINT 'TEST 20 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 1, got ' + CAST(@T20 AS varchar);

    SET @tStart = SYSUTCDATETIME();
    DELETE FROM dbo.SessionHandler WHERE ip4 IN ('192.168.30.6', '192.168.30.66');
    INSERT INTO dbo.SessionHandler (id, userAgent, host, startPage, baned, ip4, counterPage)
    VALUES (NEWID(), 'UT_AGENT_IIB_06', 'UT_HOST_IIB_06', '/banned-other-ip', 1, '192.168.30.66', 1);
    DECLARE @T21 bit = dbo.IsIpBanned('192.168.30.6');
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @T21 = 0 PRINT 'TEST 21 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returns 0 for a different banned ip4';
    ELSE PRINT 'TEST 21 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: expected 0, got ' + CAST(@T21 AS varchar);

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
