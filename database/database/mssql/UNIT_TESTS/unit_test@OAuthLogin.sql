SET QUOTED_IDENTIFIER ON
GO
PRINT 'Unit tests for spOAuthLoginOrCreateUser / UserExternalLogin'
PRINT '-----------------------------------------------------------------------------------------------------------------------------'

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Unit tests for dbo.spOAuthLoginOrCreateUser (Gmail-only external login split into UserExternalLogin)
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
-----------------------------------------------------------------------------------------------------------------------------------------------
