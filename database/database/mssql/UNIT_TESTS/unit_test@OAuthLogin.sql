SET QUOTED_IDENTIFIER ON
GO
/*
  Unit tests for dbo.spOAuthLoginOrCreateUser / dbo.UserExternalLogin (Google, Twitter,
  LinkedIn, Outlook, GitHub, Email magic-link providers).
  Uses real tables dbo.Users, dbo.UserExternalLogin, dbo.BannedUser. Each test scrubs its
  own fixture rows (by sub/email) before running, so merging into one shared transaction
  does not create cross-test interference. Transaction is rolled back at end.

  TEST  1 - first Google login creates a Users row AND a linked UserExternalLogin row
  TEST  2 - returning Google login (same provider+sub) reuses the user, no duplicate login row
  TEST  3 - Google login for an email that already has a Users row links to it (no new user)
  TEST  4 - first Twitter login (no real email -> synthetic) creates user with handle userName
  TEST  5 - returning Twitter login reuses user; same sub under Google stays a separate account
  TEST  6 - first LinkedIn login creates user with display-name userName
  TEST  7 - first Outlook login creates user with display-name userName
  TEST  8 - first GitHub login creates user with display-name userName
  TEST  9 - first Email (magic-link) login creates user keyed by address
  TEST 10 - Google userName is the display name, and returning login self-heals an email-as-userName row
  TEST 11 - a banned email is refused at sign-in (proc raises an error), no user created
  TEST 12 - re-auth after soft-delete creates a brand-new user, not the old one
*/
SET NOCOUNT ON;

DECLARE @tStart    datetime2;
DECLARE @ElapsedMs int;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------
    -- TEST 1: first Google login creates a Users row AND a linked UserExternalLogin row
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub1 nvarchar(256) = N'UT_SUB_0001';
    DECLARE @Email1 nvarchar(255) = N'ut_oauth_new@example.com';
    DECLARE @UserId1 uniqueidentifier, @UserName1 nvarchar(256), @IsNew1 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub1;
    DELETE FROM dbo.Users WHERE email = @Email1;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Google', @providerUserId=@Sub1, @email=@Email1, @givenName=N'New', @familyName=N'Angler',
          @userId=@UserId1 OUTPUT, @userName=@UserName1 OUTPUT, @isNewUser=@IsNew1 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew1 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId1 AND email = @Email1)
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId1 AND provider = N'Google' AND providerUserId = @Sub1 AND email = @Email1 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 1 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first Google login created user + linked external login';
    ELSE
        PRINT 'TEST 1 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew1 AS varchar),'NULL');

    -- ----------------------------------------------------------------
    -- TEST 2: returning Google login (same provider+sub) reuses the user, no duplicate login row
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub2 nvarchar(256) = N'UT_SUB_0002';
    DECLARE @Email2 nvarchar(255) = N'ut_oauth_ret@example.com';
    DECLARE @Uid2a uniqueidentifier, @Uid2b uniqueidentifier, @Un2 nvarchar(256), @New2a bit, @New2b bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub2;
    DELETE FROM dbo.Users WHERE email = @Email2;
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Google', @providerUserId=@Sub2, @email=@Email2, @userId=@Uid2a OUTPUT, @userName=@Un2 OUTPUT, @isNewUser=@New2a OUTPUT;
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Google', @providerUserId=@Sub2, @email=@Email2, @userId=@Uid2b OUTPUT, @userName=@Un2 OUTPUT, @isNewUser=@New2b OUTPUT;
    DECLARE @LoginCnt2 int = (SELECT COUNT(*) FROM dbo.UserExternalLogin WHERE provider = N'Google' AND providerUserId = @Sub2);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @New2a = 1 AND @New2b = 0 AND @Uid2a = @Uid2b AND @LoginCnt2 = 1
        PRINT 'TEST 2 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: returning login reused user, single external login row';
    ELSE
        PRINT 'TEST 2 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: new=' + ISNULL(CAST(@New2a AS varchar),'?') + '/' + ISNULL(CAST(@New2b AS varchar),'?') + ' sameId=' + CASE WHEN @Uid2a=@Uid2b THEN '1' ELSE '0' END + ' loginCnt=' + CAST(@LoginCnt2 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 3: Google login for an email that already has a Users row links to it (no new user)
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub3 nvarchar(256) = N'UT_SUB_0003';
    DECLARE @Email3 nvarchar(255) = N'ut_oauth_link@example.com';
    DECLARE @Existing3 uniqueidentifier = NEWID();
    DECLARE @Uid3 uniqueidentifier, @Un3 nvarchar(256), @New3 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub3;
    DELETE FROM dbo.Users WHERE email = @Email3;
    INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType)
    VALUES (@Existing3, 'ut_link_user', HASHBYTES('MD5','ut*pwd'), 'Linked', 'User', @Email3, 'q', 0x0024, 'Local');
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Google', @providerUserId=@Sub3, @email=@Email3, @userId=@Uid3 OUTPUT, @userName=@Un3 OUTPUT, @isNewUser=@New3 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @New3 = 0 AND @Uid3 = @Existing3
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @Existing3 AND provider = N'Google' AND providerUserId = @Sub3)
        PRINT 'TEST 3 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: linked external login to existing user by email';
    ELSE
        PRINT 'TEST 3 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: new=' + ISNULL(CAST(@New3 AS varchar),'?') + ' uid=' + ISNULL(CAST(@Uid3 AS varchar),'NULL');

    -- ----------------------------------------------------------------
    -- TEST 4: first Twitter login (synthetic email) creates user with handle userName
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub4 nvarchar(256) = N'UT_TW_0004';
    DECLARE @Email4 nvarchar(255) = N'twitter_ut0004@users.fishfind.info';
    DECLARE @Handle4 nvarchar(64) = N'CoolAngler';
    DECLARE @UserId4 uniqueidentifier, @UserName4 nvarchar(256), @IsNew4 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub4;
    DELETE FROM dbo.Users WHERE email = @Email4;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Twitter', @providerUserId=@Sub4, @email=@Email4, @givenName=@Handle4,
          @userId=@UserId4 OUTPUT, @userName=@UserName4 OUTPUT, @isNewUser=@IsNew4 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew4 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId4 AND email = @Email4 AND userName = @Handle4)
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId4 AND provider = N'Twitter' AND providerUserId = @Sub4 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 4 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first Twitter login created user with handle userName';
    ELSE
        PRINT 'TEST 4 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew4 AS varchar),'NULL') + ' userName=' + ISNULL(@UserName4,'NULL');

    -- ----------------------------------------------------------------
    -- TEST 5: returning Twitter login reuses user; Google with same sub is a separate account
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub5 nvarchar(256) = N'UT_DUP_0005';
    DECLARE @TwMail5 nvarchar(255) = N'twitter_ut0005@users.fishfind.info';
    DECLARE @GgMail5 nvarchar(255) = N'ut_oauth_0005@example.com';
    DECLARE @Tw5a uniqueidentifier, @Tw5b uniqueidentifier, @Gg5 uniqueidentifier, @Un5 nvarchar(256), @N5a bit, @N5b bit, @Ng5 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub5;
    DELETE FROM dbo.Users WHERE email IN (@TwMail5, @GgMail5);
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Twitter', @providerUserId=@Sub5, @email=@TwMail5, @givenName=N'TwUser', @userId=@Tw5a OUTPUT, @userName=@Un5 OUTPUT, @isNewUser=@N5a OUTPUT;
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Twitter', @providerUserId=@Sub5, @email=@TwMail5, @givenName=N'TwUser', @userId=@Tw5b OUTPUT, @userName=@Un5 OUTPUT, @isNewUser=@N5b OUTPUT;
    EXEC dbo.spOAuthLoginOrCreateUser @provider=N'Google', @providerUserId=@Sub5, @email=@GgMail5, @userId=@Gg5 OUTPUT, @userName=@Un5 OUTPUT, @isNewUser=@Ng5 OUTPUT;
    DECLARE @TwLoginCnt5 int = (SELECT COUNT(*) FROM dbo.UserExternalLogin WHERE provider = N'Twitter' AND providerUserId = @Sub5);
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @N5a = 1 AND @N5b = 0 AND @Tw5a = @Tw5b AND @TwLoginCnt5 = 1 AND @Ng5 = 1 AND @Gg5 <> @Tw5a
        PRINT 'TEST 5 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Twitter reuse + provider-scoped sub confirmed';
    ELSE
        PRINT 'TEST 5 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: tw_new=' + ISNULL(CAST(@N5a AS varchar),'?') + '/' + ISNULL(CAST(@N5b AS varchar),'?') + ' gg_new=' + ISNULL(CAST(@Ng5 AS varchar),'?');

    -- ----------------------------------------------------------------
    -- TEST 6: first LinkedIn login creates user with display-name userName
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub6 nvarchar(256) = N'UT_LI_0006';
    DECLARE @Email6 nvarchar(255) = N'ut_oauth_li@example.com';
    DECLARE @UserId6 uniqueidentifier, @UserName6 nvarchar(256), @IsNew6 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub6;
    DELETE FROM dbo.Users WHERE email = @Email6;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'LinkedIn', @providerUserId=@Sub6, @email=@Email6, @givenName=N'Linked', @familyName=N'Angler',
          @userId=@UserId6 OUTPUT, @userName=@UserName6 OUTPUT, @isNewUser=@IsNew6 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew6 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId6 AND email = @Email6 AND userName = N'Linked Angler')
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId6 AND provider = N'LinkedIn' AND providerUserId = @Sub6 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 6 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first LinkedIn login created user with display-name userName';
    ELSE
        PRINT 'TEST 6 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew6 AS varchar),'NULL') + ' userName=' + ISNULL(@UserName6,'NULL');

    -- ----------------------------------------------------------------
    -- TEST 7: first Outlook login creates user with display-name userName
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub7 nvarchar(256) = N'UT_OL_0007';
    DECLARE @Email7 nvarchar(255) = N'ut_outlook_angler@outlook.com';
    DECLARE @UserId7 uniqueidentifier, @UserName7 nvarchar(256), @IsNew7 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub7;
    DELETE FROM dbo.Users WHERE email = @Email7;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Outlook', @providerUserId=@Sub7, @email=@Email7, @givenName=N'Outlook', @familyName=N'Angler',
          @userId=@UserId7 OUTPUT, @userName=@UserName7 OUTPUT, @isNewUser=@IsNew7 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew7 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId7 AND email = @Email7 AND userName = N'Outlook Angler')
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId7 AND provider = N'Outlook' AND providerUserId = @Sub7 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 7 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first Outlook login created user with display-name userName';
    ELSE
        PRINT 'TEST 7 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew7 AS varchar),'NULL') + ' userName=' + ISNULL(@UserName7,'NULL');

    -- ----------------------------------------------------------------
    -- TEST 8: first GitHub login creates user with display-name userName
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub8 nvarchar(256) = N'UT_GH_0008';
    DECLARE @Email8 nvarchar(255) = N'ut_oauth_gh@example.com';
    DECLARE @UserId8 uniqueidentifier, @UserName8 nvarchar(256), @IsNew8 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub8;
    DELETE FROM dbo.Users WHERE email = @Email8;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'GitHub', @providerUserId=@Sub8, @email=@Email8, @givenName=N'GitHub', @familyName=N'Angler',
          @userId=@UserId8 OUTPUT, @userName=@UserName8 OUTPUT, @isNewUser=@IsNew8 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew8 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId8 AND email = @Email8 AND userName = N'GitHub Angler')
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId8 AND provider = N'GitHub' AND providerUserId = @Sub8 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 8 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first GitHub login created user with display-name userName';
    ELSE
        PRINT 'TEST 8 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew8 AS varchar),'NULL') + ' userName=' + ISNULL(@UserName8,'NULL');

    -- ----------------------------------------------------------------
    -- TEST 9: first Email (magic-link) login creates user keyed by address
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Email9 nvarchar(255) = N'ut_magic_angler@example.com';
    DECLARE @UserId9 uniqueidentifier, @UserName9 nvarchar(256), @IsNew9 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Email9;
    DELETE FROM dbo.Users WHERE email = @Email9;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Email', @providerUserId=@Email9, @email=@Email9, @givenName=N'ut_magic_angler',
          @userId=@UserId9 OUTPUT, @userName=@UserName9 OUTPUT, @isNewUser=@IsNew9 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @IsNew9 = 1
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId9 AND email = @Email9)
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @UserId9 AND provider = N'Email' AND providerUserId = @Email9 AND lastLoginUtc IS NOT NULL)
        PRINT 'TEST 9 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: first Email magic-link login created user keyed by address';
    ELSE
        PRINT 'TEST 9 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@IsNew9 AS varchar),'NULL');

    -- ----------------------------------------------------------------
    -- TEST 10: Google userName is the display name; returning login self-heals email-as-userName
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub10 nvarchar(256) = N'UT_GG_0010';
    DECLARE @Email10 nvarchar(255) = N'ut_google_name@example.com';
    DECLARE @UserId10 uniqueidentifier, @UserName10 nvarchar(256), @IsNew10 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub10;
    DELETE FROM dbo.Users WHERE email = @Email10;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Google', @providerUserId=@Sub10, @email=@Email10, @givenName=N'Anton', @familyName=N'Fulton',
          @userId=@UserId10 OUTPUT, @userName=@UserName10 OUTPUT, @isNewUser=@IsNew10 OUTPUT;
    DECLARE @FirstOk10 bit = CASE WHEN @IsNew10 = 1 AND @UserName10 = N'Anton Fulton' THEN 1 ELSE 0 END;
    UPDATE dbo.Users SET userName = @Email10 WHERE id = @UserId10;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Google', @providerUserId=@Sub10, @email=@Email10, @givenName=N'Anton', @familyName=N'Fulton',
          @userId=@UserId10 OUTPUT, @userName=@UserName10 OUTPUT, @isNewUser=@IsNew10 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @FirstOk10 = 1 AND @IsNew10 = 0 AND @UserName10 = N'Anton Fulton'
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @UserId10 AND userName = N'Anton Fulton')
        PRINT 'TEST 10 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Google userName is display name and self-heals on return';
    ELSE
        PRINT 'TEST 10 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: firstOk=' + CAST(@FirstOk10 AS varchar) + ' isNew=' + ISNULL(CAST(@IsNew10 AS varchar),'NULL') + ' userName=' + ISNULL(@UserName10,'NULL');

    -- ----------------------------------------------------------------
    -- TEST 11: a banned email is refused at sign-in (proc raises an error), no user created
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Email11 nvarchar(255) = N'ut_banned_user@example.com';
    DECLARE @Sub11 nvarchar(256) = N'UT_BAN_0011';
    DECLARE @Uid11 uniqueidentifier, @Un11 nvarchar(256), @New11 bit;
    DECLARE @Raised11 bit = 0;
    DELETE FROM dbo.BannedUser WHERE email = @Email11;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub11;
    DELETE FROM dbo.Users WHERE email = @Email11;
    INSERT INTO dbo.BannedUser (email) VALUES (@Email11);
    BEGIN TRY
        EXEC dbo.spOAuthLoginOrCreateUser
              @provider=N'Google', @providerUserId=@Sub11, @email=@Email11, @givenName=N'Banned', @familyName=N'User',
              @userId=@Uid11 OUTPUT, @userName=@Un11 OUTPUT, @isNewUser=@New11 OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Raised11 = 1;
    END CATCH
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @Raised11 = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Users WHERE email = @Email11)
        PRINT 'TEST 11 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: banned email refused, no user created';
    ELSE
        PRINT 'TEST 11 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: raised=' + CAST(@Raised11 AS varchar);

    -- ----------------------------------------------------------------
    -- TEST 12: re-auth after soft-delete creates a brand-new user, not the old one
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub12 nvarchar(256) = N'UT_DEL_0012';
    DECLARE @Email12 nvarchar(255) = N'ut_softdelete@example.com';
    DECLARE @FirstId12 uniqueidentifier, @SecondId12 uniqueidentifier, @UserName12 nvarchar(256), @IsNew12 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub12;
    DELETE FROM dbo.Users WHERE email = @Email12;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Google', @providerUserId=@Sub12, @email=@Email12, @givenName=N'Dora', @familyName=N'Deleted',
          @userId=@FirstId12 OUTPUT, @userName=@UserName12 OUTPUT, @isNewUser=@IsNew12 OUTPUT;
    DECLARE @FirstOk12 bit = @IsNew12;
    UPDATE dbo.Users SET deleted = 1, deletedUtc = SYSUTCDATETIME() WHERE id = @FirstId12;
    DELETE FROM dbo.UserExternalLogin WHERE userId = @FirstId12;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Google', @providerUserId=@Sub12, @email=@Email12, @givenName=N'Dora', @familyName=N'Deleted',
          @userId=@SecondId12 OUTPUT, @userName=@UserName12 OUTPUT, @isNewUser=@IsNew12 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @FirstOk12 = 1 AND @IsNew12 = 1 AND @SecondId12 <> @FirstId12
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @FirstId12 AND deleted = 1)
       AND EXISTS (SELECT 1 FROM dbo.Users WHERE id = @SecondId12 AND deleted = 0 AND email = @Email12)
        PRINT 'TEST 12 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: re-auth after soft-delete created a new profile';
    ELSE
        PRINT 'TEST 12 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: firstOk=' + CAST(@FirstOk12 AS varchar) + ' isNew=' + ISNULL(CAST(@IsNew12 AS varchar),'NULL') + ' sameId=' + CASE WHEN @SecondId12=@FirstId12 THEN '1' ELSE '0' END;

    -- ----------------------------------------------------------------
    -- TEST 13: Facebook provider is accepted (CH_UEL_provider) and creates a user + link
    -- ----------------------------------------------------------------
    SET @tStart = SYSUTCDATETIME();
    DECLARE @Sub13 nvarchar(256) = N'UT_FB_0013';
    DECLARE @Email13 nvarchar(255) = N'ut_facebook@example.com';
    DECLARE @Uid13 uniqueidentifier, @Un13 nvarchar(256), @New13 bit;
    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @Sub13;
    DELETE FROM dbo.Users WHERE email = @Email13;
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider=N'Facebook', @providerUserId=@Sub13, @email=@Email13, @givenName=N'Fred', @familyName=N'Booker',
          @userId=@Uid13 OUTPUT, @userName=@Un13 OUTPUT, @isNewUser=@New13 OUTPUT;
    SET @ElapsedMs = DATEDIFF(millisecond, @tStart, SYSUTCDATETIME());
    IF @New13 = 1 AND @Un13 = N'Fred Booker'
       AND EXISTS (SELECT 1 FROM dbo.UserExternalLogin WHERE userId = @Uid13 AND provider = N'Facebook' AND providerUserId = @Sub13)
        PRINT 'TEST 13 PASS [' + CAST(@ElapsedMs AS varchar) + 'ms]: Facebook provider accepted, user + link created';
    ELSE
        PRINT 'TEST 13 FAIL [' + CAST(@ElapsedMs AS varchar) + 'ms]: isNew=' + ISNULL(CAST(@New13 AS varchar),'NULL') + ' userName=' + ISNULL(@Un13,'NULL');

    ROLLBACK TRANSACTION;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'EXCEPTION during test: ' + ERROR_MESSAGE()
        + '  (proc=' + ISNULL(ERROR_PROCEDURE(), 'n/a')
        + ', line='  + CAST(ERROR_LINE() AS varchar) + ')';
END CATCH;
