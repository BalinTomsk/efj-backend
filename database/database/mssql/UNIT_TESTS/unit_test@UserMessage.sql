SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for private user-to-user messaging: dbo.user_message, dbo.user_message_block,
  dbo.user_send_ban, dbo.sp_send_user_message, dbo.sp_block_user_sender, dbo.sp_unblock_user_sender,
  dbo.sp_mark_user_messages_read, dbo.sp_admin_unban_user, dbo.fn_user_message_inbox,
  dbo.fn_user_message_unread_count, dbo.fn_user_is_send_banned.

  Recipients must be real dbo.Users rows (the send proc resolves/validates the recipient), so each
  test inserts a minimal Users fixture. Senders can be any guid. Each test is its own named
  transaction, rolled back at the end -- state restored, tests independent.

  TEST 1 - sp_send_user_message delivers a message; inbox lists it; unread count = 1
  TEST 2 - sp_send_user_message resolves the recipient by userName
  TEST 3 - empty text, self-send, and unknown recipient are rejected (nothing delivered)
  TEST 4 - a recipient block stops the sender (status 'blocked', not delivered)
  TEST 5 - unblock restores delivery
  TEST 6 - sending over 50 messages auto-bans the account (51st flags it; 52nd is 'banned')
  TEST 7 - sp_admin_unban_user lifts the ban and delivery resumes
  TEST 8 - sp_mark_user_messages_read clears the unread count
*/

-- helper: minimal Users fixture is inlined per test (dbo.Users has many NOT NULL columns)

-- ============================================================================
-- TEST 1: sp_send_user_message delivers; inbox lists it; unread count = 1
-- ============================================================================
BEGIN TRAN UM_Test01
    declare @test_name sysname = N'UM_Test01 [sp_send_user_message] : delivers, inbox + unread count'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status varchar(20), @Banned bit, @InboxCnt int, @Unread int, @Txt nvarchar(2000);
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender1 uniqueidentifier = NEWID();
DECLARE @Rcpt1   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt1, N'um_rcpt_t1', 0x00000000000000000000000000000000, N'F', N'L', N'r1@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

CREATE TABLE #r1 (status varchar(20), banned bit);
INSERT INTO #r1 EXEC dbo.sp_send_user_message @from=@Sender1, @text=N'hello there', @to_id=@Rcpt1;
SELECT @Status=status, @Banned=banned FROM #r1;
DROP TABLE #r1;

SELECT @InboxCnt = COUNT(*) FROM dbo.fn_user_message_inbox(@Rcpt1);
SELECT @Txt = user_message_text FROM dbo.fn_user_message_inbox(@Rcpt1);
SET @Unread = dbo.fn_user_message_unread_count(@Rcpt1);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @Status <> 'sent' OR @Banned <> 0 OR @InboxCnt <> 1 OR @Unread <> 1 OR @Txt <> N'hello there'
   RAISERROR ('TEST 1 FAIL [%dms]: status=%s inbox=%d unread=%d', 16, -1, @ElapsedMs, @Status, @InboxCnt, @Unread)
ELSE
    print 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: message delivered, inbox + unread count correct'

ROLLBACK TRAN UM_Test01
GO

-- ============================================================================
-- TEST 2: sp_send_user_message resolves the recipient by userName
-- ============================================================================
BEGIN TRAN UM_Test02
    declare @test_name sysname = N'UM_Test02 [sp_send_user_message] : resolves recipient by userName'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status varchar(20), @InboxCnt int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender2 uniqueidentifier = NEWID();
DECLARE @Rcpt2   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt2, N'um_rcpt_t2', 0x00000000000000000000000000000000, N'F', N'L', N'r2@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

CREATE TABLE #r2 (status varchar(20), banned bit);
INSERT INTO #r2 EXEC dbo.sp_send_user_message @from=@Sender2, @text=N'by name', @to_name=N'um_rcpt_t2';
SELECT @Status=status FROM #r2;
DROP TABLE #r2;
SELECT @InboxCnt = COUNT(*) FROM dbo.fn_user_message_inbox(@Rcpt2);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @Status <> 'sent' OR @InboxCnt <> 1
   RAISERROR ('TEST 2 FAIL [%dms]: status=%s inbox=%d', 16, -1, @ElapsedMs, @Status, @InboxCnt)
ELSE
    print 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: recipient resolved by userName, delivered'

ROLLBACK TRAN UM_Test02
GO

-- ============================================================================
-- TEST 3: empty text, self-send, unknown recipient are rejected
-- ============================================================================
BEGIN TRAN UM_Test03
    declare @test_name sysname = N'UM_Test03 [sp_send_user_message] : empty/self/unknown rejected'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Empty varchar(20), @Self varchar(20), @Unknown varchar(20), @Delivered int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @U3 uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@U3, N'um_rcpt_t3', 0x00000000000000000000000000000000, N'F', N'L', N'r3@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

CREATE TABLE #r3 (status varchar(20), banned bit);
INSERT INTO #r3 EXEC dbo.sp_send_user_message @from=@U3, @text=N'   ', @to_id=@U3;                  SELECT @Empty=status FROM #r3; DELETE FROM #r3;
INSERT INTO #r3 EXEC dbo.sp_send_user_message @from=@U3, @text=N'hi', @to_id=@U3;                   SELECT @Self=status FROM #r3;  DELETE FROM #r3;
INSERT INTO #r3 EXEC dbo.sp_send_user_message @from=@U3, @text=N'hi', @to_name=N'no_such_user_xyz'; SELECT @Unknown=status FROM #r3;
DROP TABLE #r3;
SELECT @Delivered = COUNT(*) FROM dbo.user_message WHERE user_message_from = @U3;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @Empty <> 'empty' OR @Self <> 'self' OR @Unknown <> 'no_recipient' OR @Delivered <> 0
   RAISERROR ('TEST 3 FAIL [%dms]: empty=%s self=%s unknown=%s delivered=%d', 16, -1, @ElapsedMs, @Empty, @Self, @Unknown, @Delivered)
ELSE
    print 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: empty/self/unknown all rejected, nothing delivered'

ROLLBACK TRAN UM_Test03
GO

-- ============================================================================
-- TEST 4: a recipient block stops the sender
-- ============================================================================
BEGIN TRAN UM_Test04
    declare @test_name sysname = N'UM_Test04 [sp_block_user_sender] : block stops delivery'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status varchar(20), @Delivered int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender4 uniqueidentifier = NEWID();
DECLARE @Rcpt4   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt4, N'um_rcpt_t4', 0x00000000000000000000000000000000, N'F', N'L', N'r4@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

EXEC dbo.sp_block_user_sender @userid=@Rcpt4, @blockedid=@Sender4;   -- recipient blocks the sender
CREATE TABLE #r4 (status varchar(20), banned bit);
INSERT INTO #r4 EXEC dbo.sp_send_user_message @from=@Sender4, @text=N'let me in', @to_id=@Rcpt4;
SELECT @Status=status FROM #r4;
DROP TABLE #r4;
SELECT @Delivered = COUNT(*) FROM dbo.user_message WHERE user_message_from = @Sender4 AND user_message_to = @Rcpt4;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @Status <> 'blocked' OR @Delivered <> 0
   RAISERROR ('TEST 4 FAIL [%dms]: status=%s delivered=%d', 16, -1, @ElapsedMs, @Status, @Delivered)
ELSE
    print 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: blocked sender could not deliver'

ROLLBACK TRAN UM_Test04
GO

-- ============================================================================
-- TEST 5: unblock restores delivery
-- ============================================================================
BEGIN TRAN UM_Test05
    declare @test_name sysname = N'UM_Test05 [sp_unblock_user_sender] : unblock restores delivery'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Status varchar(20), @Delivered int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender5 uniqueidentifier = NEWID();
DECLARE @Rcpt5   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt5, N'um_rcpt_t5', 0x00000000000000000000000000000000, N'F', N'L', N'r5@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

EXEC dbo.sp_block_user_sender   @userid=@Rcpt5, @blockedid=@Sender5;
EXEC dbo.sp_unblock_user_sender @userid=@Rcpt5, @blockedid=@Sender5;
CREATE TABLE #r5 (status varchar(20), banned bit);
INSERT INTO #r5 EXEC dbo.sp_send_user_message @from=@Sender5, @text=N'thanks', @to_id=@Rcpt5;
SELECT @Status=status FROM #r5;
DROP TABLE #r5;
SELECT @Delivered = COUNT(*) FROM dbo.user_message WHERE user_message_from = @Sender5 AND user_message_to = @Rcpt5;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @Status <> 'sent' OR @Delivered <> 1
   RAISERROR ('TEST 5 FAIL [%dms]: status=%s delivered=%d', 16, -1, @ElapsedMs, @Status, @Delivered)
ELSE
    print 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: unblock restored delivery'

ROLLBACK TRAN UM_Test05
GO

-- ============================================================================
-- TEST 6: sending over 50 messages auto-bans the account
-- ============================================================================
BEGIN TRAN UM_Test06
    declare @test_name sysname = N'UM_Test06 [sp_send_user_message] : >50 messages auto-bans the account'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @Banned51 int, @IsBanned int, @Status52 varchar(20), @Delivered int;   -- int (not bit): RAISERROR %d args must not be bit
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender6 uniqueidentifier = NEWID();
DECLARE @Rcpt6   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt6, N'um_rcpt_t6', 0x00000000000000000000000000000000, N'F', N'L', N'r6@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

CREATE TABLE #r6 (status varchar(20), banned bit);
DECLARE @i int = 1;
WHILE @i <= 51                                   -- 51 sends: the 51st tips it over 50
BEGIN
    DELETE FROM #r6;
    INSERT INTO #r6 EXEC dbo.sp_send_user_message @from=@Sender6, @text=N'spam', @to_id=@Rcpt6;
    SET @i += 1;
END
SELECT @Banned51 = banned FROM #r6;              -- 51st send should report banned = 1
SET @IsBanned = dbo.fn_user_is_send_banned(@Sender6);
DELETE FROM #r6;
INSERT INTO #r6 EXEC dbo.sp_send_user_message @from=@Sender6, @text=N'still going', @to_id=@Rcpt6;  -- 52nd blocked
SELECT @Status52 = status FROM #r6;
DROP TABLE #r6;
SELECT @Delivered = COUNT(*) FROM dbo.user_message WHERE user_message_from = @Sender6;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

-- 51 delivered (the tipping message still goes through), account banned, 52nd rejected
IF @Banned51 <> 1 OR @IsBanned <> 1 OR @Status52 <> 'banned' OR @Delivered <> 51
   RAISERROR ('TEST 6 FAIL [%dms]: banned51=%d isBanned=%d status52=%s delivered=%d', 16, -1, @ElapsedMs, @Banned51, @IsBanned, @Status52, @Delivered)
ELSE
    print 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: 51st send auto-banned the account, 52nd rejected'

ROLLBACK TRAN UM_Test06
GO

-- ============================================================================
-- TEST 7: sp_admin_unban_user lifts the ban and delivery resumes
-- ============================================================================
BEGIN TRAN UM_Test07
    declare @test_name sysname = N'UM_Test07 [sp_admin_unban_user] : admin unban restores sending'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @BannedBefore int, @BannedAfter int, @Status varchar(20);   -- int (not bit): RAISERROR %d args must not be bit
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender7 uniqueidentifier = NEWID();
DECLARE @Rcpt7   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt7, N'um_rcpt_t7', 0x00000000000000000000000000000000, N'F', N'L', N'r7@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);
INSERT INTO dbo.user_send_ban (user_send_ban_userid, user_send_ban_reason) VALUES (@Sender7, N'test');

SET @BannedBefore = dbo.fn_user_is_send_banned(@Sender7);
EXEC dbo.sp_admin_unban_user @userid=@Sender7;
SET @BannedAfter = dbo.fn_user_is_send_banned(@Sender7);
CREATE TABLE #r7 (status varchar(20), banned bit);
INSERT INTO #r7 EXEC dbo.sp_send_user_message @from=@Sender7, @text=N'back', @to_id=@Rcpt7;
SELECT @Status = status FROM #r7;
DROP TABLE #r7;

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @BannedBefore <> 1 OR @BannedAfter <> 0 OR @Status <> 'sent'
   RAISERROR ('TEST 7 FAIL [%dms]: before=%d after=%d status=%s', 16, -1, @ElapsedMs, @BannedBefore, @BannedAfter, @Status)
ELSE
    print 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: admin unban cleared the ban, sending resumed'

ROLLBACK TRAN UM_Test07
GO

-- ============================================================================
-- TEST 8: sp_mark_user_messages_read clears the unread count
-- ============================================================================
BEGIN TRAN UM_Test08
    declare @test_name sysname = N'UM_Test08 [sp_mark_user_messages_read] : marks inbox read'
DECLARE @tStart datetime2, @ElapsedMs int;
DECLARE @UnreadBefore int, @UnreadAfter int;
BEGIN TRY  SET NOCOUNT ON;
SET @tStart = SYSUTCDATETIME();

DECLARE @Sender8 uniqueidentifier = NEWID();
DECLARE @Rcpt8   uniqueidentifier = NEWID();
INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType, deleted)
VALUES (@Rcpt8, N'um_rcpt_t8', 0x00000000000000000000000000000000, N'F', N'L', N'r8@test', N'q', 0x00000000000000000000000000000000, N'Local', 0);

CREATE TABLE #r8 (status varchar(20), banned bit);
INSERT INTO #r8 EXEC dbo.sp_send_user_message @from=@Sender8, @text=N'one', @to_id=@Rcpt8; DELETE FROM #r8;
INSERT INTO #r8 EXEC dbo.sp_send_user_message @from=@Sender8, @text=N'two', @to_id=@Rcpt8;
DROP TABLE #r8;

SET @UnreadBefore = dbo.fn_user_message_unread_count(@Rcpt8);
EXEC dbo.sp_mark_user_messages_read @userid=@Rcpt8;
SET @UnreadAfter = dbo.fn_user_message_unread_count(@Rcpt8);

END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState
         , @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage
END CATCH
SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());

IF @UnreadBefore <> 2 OR @UnreadAfter <> 0
   RAISERROR ('TEST 8 FAIL [%dms]: before=%d after=%d', 16, -1, @ElapsedMs, @UnreadBefore, @UnreadAfter)
ELSE
    print 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: mark-read cleared the unread count'

ROLLBACK TRAN UM_Test08
GO
