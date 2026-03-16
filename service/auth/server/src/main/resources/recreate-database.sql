/*
    Recreates the auth service database objects for Microsoft SQL Server.
    Run this manually against the target database when a full reset is needed.
*/

IF OBJECT_ID('users', 'U') IS NOT NULL
BEGIN
    DROP TABLE users;
END
GO

CREATE TABLE users (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    username NVARCHAR(255) NOT NULL UNIQUE,
    email NVARCHAR(255) NOT NULL UNIQUE,
    password NVARCHAR(255) NOT NULL,
    ip4 NVARCHAR(64) NULL,
    ip6 NVARCHAR(128) NULL,
    titul NVARCHAR(255) NULL,
    last_visit DATETIMEOFFSET NULL,
    question NVARCHAR(255) NULL,
    answer NVARCHAR(255) NULL,
    cell NVARCHAR(255) NULL,
    suspended BIT NOT NULL CONSTRAINT DF_users_suspended DEFAULT 0,
    agent NVARCHAR(1024) NULL,
    confirmed BIT NOT NULL CONSTRAINT DF_users_confirmed DEFAULT 0,
    confirmation_token NVARCHAR(255) NULL,
    created_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_created_at DEFAULT SYSDATETIMEOFFSET(),
    updated_at DATETIMEOFFSET NOT NULL CONSTRAINT DF_users_updated_at DEFAULT SYSDATETIMEOFFSET()
);
GO

CREATE INDEX IX_users_ip4 ON users (ip4);
GO

CREATE INDEX IX_users_ip6 ON users (ip6);
GO

CREATE INDEX IX_users_confirmation_token ON users (confirmation_token);
GO

CREATE INDEX IX_users_suspended_ip4 ON users (suspended, ip4);
GO

CREATE INDEX IX_users_suspended_ip6 ON users (suspended, ip6);
GO
