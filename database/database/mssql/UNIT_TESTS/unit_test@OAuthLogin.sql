SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for spOAuthLoginOrCreateUser / UserExternalLogin'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.spOAuthLoginOrCreateUser (Google + Twitter + LinkedIn + Outlook + GitHub external login via UserExternalLogin)
-----------------------------------------------------------------------------------------------------------------------------------------------

-- TEST 1: First Google login creates a Users row AND a linked UserExternalLogin row
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL1
DECLARE @test_name SYSNAME = 'TestOAL1 [spOAuthLoginOrCreateUser] first Google login creates user + external login';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub          nvarchar(256) = N'UT_SUB_0001';
    DECLARE @email        nvarchar(255) = N'ut_oauth_new@example.com';
    DECLARE @userId       uniqueidentifier;
    DECLARE @userName     nvarchar(256);
    DECLARE @isNewUser    bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'Google'
        , @providerUserId = @sub
        , @email          = @email
        , @givenName      = N'New'
        , @familyName     = N'Angler'
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1, actual ' + ISNULL(CAST(@isNewUser AS varchar(1)), 'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row for returned @userId/email';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'Google' AND providerUserId = @sub
          AND email = 'ut_oauth_new@example.com' AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL1
GO


-- TEST 2: Returning Google login (same provider+sub) reuses the user, no duplicate login row
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL2
DECLARE @test_name SYSNAME = 'TestOAL2 [spOAuthLoginOrCreateUser] returning login reuses user, no duplicate external login';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub       nvarchar(256) = N'UT_SUB_0002';
    DECLARE @email     nvarchar(255) = N'ut_oauth_ret@example.com';
    DECLARE @uid1      uniqueidentifier, @uid2 uniqueidentifier;
    DECLARE @un        nvarchar(256);
    DECLARE @new1      bit, @new2 bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Google', @providerUserId = @sub, @email = @email
        , @userId = @uid1 OUTPUT, @userName = @un OUTPUT, @isNewUser = @new1 OUTPUT;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Google', @providerUserId = @sub, @email = @email
        , @userId = @uid2 OUTPUT, @userName = @un OUTPUT, @isNewUser = @new2 OUTPUT;

    IF @new1 <> 1 OR @new2 <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected isNew 1 then 0, actual '
            + ISNULL(CAST(@new1 AS varchar(1)),'NULL') + '/' + ISNULL(CAST(@new2 AS varchar(1)),'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF @uid1 <> @uid2
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected same @userId on both calls';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF (SELECT COUNT(*) FROM dbo.UserExternalLogin WHERE provider = N'Google' AND providerUserId = @sub) <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected exactly one external login row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL2
GO


-- TEST 3: Google login for an email that already has a Users row links to it (no new user)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL3
DECLARE @test_name SYSNAME = 'TestOAL3 [spOAuthLoginOrCreateUser] links external login to existing user by email';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub       nvarchar(256) = N'UT_SUB_0003';
    DECLARE @email     nvarchar(255) = N'ut_oauth_link@example.com';
    DECLARE @existing  uniqueidentifier = NEWID();
    DECLARE @uid       uniqueidentifier;
    DECLARE @un        nvarchar(256);
    DECLARE @isNew     bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    -- pre-existing (e.g. legacy/local) account with this email, no external login yet
    INSERT INTO dbo.Users (id, userName, psw, firstName, lastName, email, question, answer, authType)
    VALUES (@existing, 'ut_link_user', HASHBYTES('MD5','ut*pwd'), 'Linked', 'User', @email, 'q', 0x0024, 'Local');

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Google', @providerUserId = @sub, @email = @email
        , @userId = @uid OUTPUT, @userName = @un OUTPUT, @isNewUser = @isNew OUTPUT;

    IF @isNew <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 0 (linked existing)';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF @uid <> @existing
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected returned @userId to equal existing user id';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @existing AND provider = N'Google' AND providerUserId = @sub)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected external login linked to existing user';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL3
GO


-- TEST 4: First Twitter login (no real email -> synthetic) creates user whose userName is the
--         display name (the @handle), plus a UserExternalLogin row with provider='Twitter'
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL4
DECLARE @test_name SYSNAME = 'TestOAL4 [spOAuthLoginOrCreateUser] first Twitter login creates user with handle userName';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub        nvarchar(256) = N'UT_TW_0004';
    DECLARE @email      nvarchar(255) = N'twitter_ut0004@users.fishfind.info';  -- synthetic, supplied by caller
    DECLARE @handle     nvarchar(64)  = N'CoolAngler';
    DECLARE @userId     uniqueidentifier;
    DECLARE @userName   nvarchar(256);
    DECLARE @isNewUser  bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'Twitter'
        , @providerUserId = @sub
        , @email          = @email
        , @givenName      = @handle      -- caller passes the X display name / @handle here
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email AND userName = @handle)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row with synthetic email and handle userName, got userName=' + ISNULL(@userName,'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'Twitter' AND providerUserId = @sub
          AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked Twitter UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL4
GO


-- TEST 5: Returning Twitter login (same provider+sub) reuses the user, no duplicate login row,
--         and a Google login with the SAME sub string stays a separate account (provider-scoped)
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL5
DECLARE @test_name SYSNAME = 'TestOAL5 [spOAuthLoginOrCreateUser] returning Twitter login reuses user; provider-scoped sub';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub      nvarchar(256) = N'UT_DUP_0005';
    DECLARE @twMail   nvarchar(255) = N'twitter_ut0005@users.fishfind.info';
    DECLARE @ggMail   nvarchar(255) = N'ut_oauth_0005@example.com';
    DECLARE @tw1 uniqueidentifier, @tw2 uniqueidentifier, @gg uniqueidentifier;
    DECLARE @un nvarchar(256);
    DECLARE @n1 bit, @n2 bit, @ng bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email IN (@twMail, @ggMail);

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Twitter', @providerUserId = @sub, @email = @twMail, @givenName = N'TwUser'
        , @userId = @tw1 OUTPUT, @userName = @un OUTPUT, @isNewUser = @n1 OUTPUT;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Twitter', @providerUserId = @sub, @email = @twMail, @givenName = N'TwUser'
        , @userId = @tw2 OUTPUT, @userName = @un OUTPUT, @isNewUser = @n2 OUTPUT;

    -- same sub value but a different provider must NOT collide with the Twitter login
    EXEC dbo.spOAuthLoginOrCreateUser
          @provider = N'Google', @providerUserId = @sub, @email = @ggMail
        , @userId = @gg OUTPUT, @userName = @un OUTPUT, @isNewUser = @ng OUTPUT;

    IF @n1 <> 1 OR @n2 <> 0
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Twitter isNew 1 then 0';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF @tw1 <> @tw2
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected same @userId on repeat Twitter login';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF (SELECT COUNT(*) FROM dbo.UserExternalLogin WHERE provider = N'Twitter' AND providerUserId = @sub) <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected exactly one Twitter external login row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF @ng <> 1 OR @gg = @tw1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Google sub to create a separate user';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL5
GO


-- TEST 6: First LinkedIn login (OIDC: real email + given/family names) creates a user whose
--         userName is the display name, plus a UserExternalLogin row with provider='LinkedIn'
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL6
DECLARE @test_name SYSNAME = 'TestOAL6 [spOAuthLoginOrCreateUser] first LinkedIn login creates user with display-name userName';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub        nvarchar(256) = N'UT_LI_0006';
    DECLARE @email      nvarchar(255) = N'ut_oauth_li@example.com';
    DECLARE @userId     uniqueidentifier;
    DECLARE @userName   nvarchar(256);
    DECLARE @isNewUser  bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'LinkedIn'
        , @providerUserId = @sub
        , @email          = @email
        , @givenName      = N'Linked'
        , @familyName     = N'Angler'
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email AND userName = N'Linked Angler')
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row with display-name userName, got userName=' + ISNULL(@userName,'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'LinkedIn' AND providerUserId = @sub
          AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked LinkedIn UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL6
GO


-- TEST 7: First Outlook login (OIDC: real email + given/family names via Microsoft Graph)
--         creates a user whose userName is the display name, plus UserExternalLogin row with provider='Outlook'
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL7
DECLARE @test_name SYSNAME = 'TestOAL7 [spOAuthLoginOrCreateUser] first Outlook login creates user with display-name userName';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub        nvarchar(256) = N'UT_OL_0007';
    DECLARE @email      nvarchar(255) = N'ut_outlook_angler@outlook.com';
    DECLARE @userId     uniqueidentifier;
    DECLARE @userName   nvarchar(256);
    DECLARE @isNewUser  bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'Outlook'
        , @providerUserId = @sub
        , @email          = @email
        , @givenName      = N'Outlook'
        , @familyName     = N'Angler'
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email AND userName = N'Outlook Angler')
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row with display-name userName, got userName=' + ISNULL(@userName,'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'Outlook' AND providerUserId = @sub
          AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked Outlook UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL7
GO


-- TEST 8: First GitHub login (display name split into given/family by the callback)
--         creates a user whose userName is the display name, plus UserExternalLogin row with provider='GitHub'
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL8
DECLARE @test_name SYSNAME = 'TestOAL8 [spOAuthLoginOrCreateUser] first GitHub login creates user with display-name userName';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @sub        nvarchar(256) = N'UT_GH_0008';
    DECLARE @email      nvarchar(255) = N'ut_oauth_gh@example.com';
    DECLARE @userId     uniqueidentifier;
    DECLARE @userName   nvarchar(256);
    DECLARE @isNewUser  bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @sub;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'GitHub'
        , @providerUserId = @sub
        , @email          = @email
        , @givenName      = N'GitHub'
        , @familyName     = N'Angler'
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email AND userName = N'GitHub Angler')
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row with display-name userName, got userName=' + ISNULL(@userName,'NULL');
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'GitHub' AND providerUserId = @sub
          AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked GitHub UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL8
GO


-- TEST 9: First Email (magic-link) login: providerUserId IS the address, givenName = local part;
--         creates a user plus UserExternalLogin row with provider='Email'
-----------------------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN TestOAL9
DECLARE @test_name SYSNAME = 'TestOAL9 [spOAuthLoginOrCreateUser] first Email login creates user keyed by address';
DECLARE @fail_message nvarchar(4000);

BEGIN TRY
    SET NOCOUNT ON;

    DECLARE @email      nvarchar(255) = N'ut_magic_angler@example.com';
    DECLARE @userId     uniqueidentifier;
    DECLARE @userName   nvarchar(256);
    DECLARE @isNewUser  bit;

    DELETE l FROM dbo.UserExternalLogin l WHERE l.providerUserId = @email;
    DELETE FROM dbo.Users WHERE email = @email;

    EXEC dbo.spOAuthLoginOrCreateUser
          @provider       = N'Email'
        , @providerUserId = @email
        , @email          = @email
        , @givenName      = N'ut_magic_angler'
        , @userId         = @userId   OUTPUT
        , @userName       = @userName OUTPUT
        , @isNewUser      = @isNewUser OUTPUT;

    IF @isNewUser <> 1
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected @isNewUser = 1';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE id = @userId AND email = @email)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected Users row for returned @userId/email';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.UserExternalLogin
        WHERE userId = @userId AND provider = N'Email' AND providerUserId = @email
          AND lastLoginUtc IS NOT NULL)
    BEGIN
        SET @fail_message = 'FAILED: ' + @test_name + ' expected linked Email UserExternalLogin row';
        RAISERROR(@fail_message, 16, 1);
    END
    ELSE
        PRINT 'PASSED ' + @test_name;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_SEVERITY() AS ErrorSeverity, ERROR_STATE() AS ErrorState,
           @test_name AS ErrorProcedure, ERROR_LINE() AS ErrorLine, ERROR_MESSAGE() AS ErrorMessage;
END CATCH

ROLLBACK TRAN TestOAL9
GO
-----------------------------------------------------------------------------------------------------------------------------------------------
