# Auth Service Rebuild Specification

## Goal

This document is intended to be sufficient to rebuild the FishFind auth service from scratch with minimal ambiguity.

The target system is the current Java/Spring Boot implementation in this repository, not the original Express sample. Where behavior is intentionally different from the Express sample, this document describes the current implemented behavior.

## System Overview

The service is a stateless authentication and account-management backend with:

- registration
- email activation
- username-or-email login
- JWT bearer authentication
- profile retrieval
- profile update
- password change
- account deletion
- health/access probe endpoints
- request rate limiting
- suspended-network blocking

## Required Architecture

The rebuilt service must preserve this logical module split:

- `api`
  - shared HTTP path constants
  - DTOs used by server and client
  - authenticated user model carried in JWT parsing/generation
- `client`
  - reusable Java client for the auth HTTP API
- `server`
  - runnable Spring Boot service
  - request filters
  - security configuration
  - persistence
  - business logic
  - controllers

## Technology Constraints

- Java 21
- Spring Boot 3.x
- Spring Web
- Spring Security
- Spring JDBC
- Spring Mail
- Microsoft SQL Server
- JJWT for token signing/parsing
- BCrypt for password hashing

## Base URL Structure

- API base: `/api`
- Auth base: `/api/auth`

## Endpoint Contract

### 1. `POST /api/auth/register`

Creates a new account, stores network metadata, and sends an activation email.

Request JSON:

```json
{
  "username": "alice",
  "email": "alice@example.com",
  "password": "secret123",
  "titul": "Captain",
  "question": "River?",
  "answer": "Salmon",
  "cell": "555-0100"
}
```

Validation rules:

- `username` is required and must be non-blank
- `email` is required, non-blank, and must be a valid email address
- `password` is required, non-blank, and minimum length is 6
- `titul`, `question`, `answer`, and `cell` are optional
- optional string fields are trimmed before persistence
- null optional fields must be stored as empty strings

Behavior rules:

- extract client network metadata before registration
- if either `ip4` or `ip6` is present and any existing user already has matching `ip4` or `ip6`, reject registration
- password must be BCrypt-hashed before persistence
- generate an activation token as a UUID string
- insert the new user with `confirmed = 0`
- send activation email after successful insert
- if email send fails after insert, return error but do not roll back the inserted row

Success:

- HTTP `200`
- body:

```json
{
  "message": "Account created. Please check your email and activate your account."
}
```

Failure matrix:

- HTTP `400`
  - invalid request body / validation error
- HTTP `403`
  - `registration ignored due to network issues, please write a letter for manual registration`
- HTTP `409`
  - `Username or email already exists`
- HTTP `500`
  - `Account created in database, but sending activation email failed`

### 2. `GET /api/auth/activate/{activationToken}`

Activates an account using the stored confirmation token.

Path parameter:

- `activationToken`: required string

Behavior rules:

- if token is blank, reject
- find user by `confirmation_token`
- if no user found, reject
- if user is already confirmed, return already-activated message
- otherwise set:
  - `confirmed = 1`
  - `confirmation_token = NULL`
  - `updated_at = SYSDATETIMEOFFSET()`

Success:

- HTTP `200`
- body if newly activated:

```json
{
  "message": "Account activated successfully. You can now log in."
}
```

- body if already activated:

```json
{
  "message": "Account is already activated. You can log in now."
}
```

Failure matrix:

- HTTP `400`
  - `Activation token is required`
  - `Invalid activation link`

### 3. `POST /api/auth/login`

Authenticates using username or email and returns a JWT plus user payload.

Accepted request JSON:

```json
{
  "login": "alice",
  "password": "secret123"
}
```

Also accepted because of JSON aliasing:

```json
{
  "email": "alice@example.com",
  "password": "secret123"
}
```

Validation rules:

- `login` must be non-blank
- `password` must be non-blank

Behavior rules:

- query by `email = login OR username = login`
- if no user, return invalid credentials
- if `suspended = 1`, return endpoint not found
- if `confirmed = 0`, reject login
- compare supplied password using BCrypt
- if password mismatch, return invalid credentials
- on success:
  - compute `loginTimestamp = now`
  - update `last_visit = loginTimestamp`
  - update `updated_at = SYSDATETIMEOFFSET()`
  - reload the user from persistence
  - issue JWT containing `id`, `username`, and `email`

Success:

- HTTP `200`
- body:

```json
{
  "message": "Login successful",
  "token": "<jwt>",
  "user": {
    "id": 1,
    "username": "alice",
    "email": "alice@example.com",
    "titul": "Captain",
    "cell": "555-0100",
    "question": "River?",
    "answer": "Salmon",
    "lastVisit": "2026-03-15T22:00:00Z",
    "suspended": false,
    "createdAt": "2026-03-12T00:00:00Z",
    "updatedAt": "2026-03-15T22:00:00Z"
  }
}
```

Failure matrix:

- HTTP `401`
  - `Invalid credentials`
  - `Please activate your email before logging in`
- HTTP `404`
  - `Endpoint not found`

### 4. `GET /api/auth/validate`

Returns the authenticated user.

Auth:

- bearer token required

Behavior rules:

- JWT is parsed into authenticated principal
- authenticated principal is resolved to persisted user by `id`
- if no persisted user found, return `User not found`
- if persisted user is suspended, return `Endpoint not found`

Success:

- HTTP `200`
- body:

```json
{
  "user": {
    "id": 1,
    "username": "alice",
    "email": "alice@example.com",
    "titul": "Captain",
    "cell": "555-0100",
    "question": "River?",
    "answer": "Salmon",
    "lastVisit": "2026-03-15T22:00:00Z",
    "suspended": false,
    "createdAt": "2026-03-12T00:00:00Z",
    "updatedAt": "2026-03-15T22:00:00Z"
  }
}
```

Failure matrix:

- HTTP `401`
  - `Access token required`
- HTTP `403`
  - `Invalid or expired token`
- HTTP `404`
  - `User not found`
  - `Endpoint not found`

### 5. `GET /api/auth/profile`

Same authentication and response rules as `/api/auth/validate`.

### 6. `PUT /api/auth/profile`

Updates username and email only.

Auth:

- bearer token required

Request JSON:

```json
{
  "username": "alice2",
  "email": "alice2@example.com"
}
```

Validation rules:

- `username` required and non-blank
- `email` required, non-blank, valid email

Behavior rules:

- authenticated user must exist and not be suspended
- update only:
  - `username`
  - `email`
  - `updated_at`
- do not update:
  - `titul`
  - `cell`
  - `question`
  - `answer`
  - `ip4`
  - `ip6`
  - `agent`
- reload updated user and return full user payload

Failure matrix:

- HTTP `401`
  - `Access token required`
- HTTP `403`
  - `Invalid or expired token`
- HTTP `404`
  - `User not found`
  - `Endpoint not found`
- HTTP `409`
  - `Username or email already exists`

### 7. `PUT /api/auth/change-password`

Changes the authenticated user password.

Auth:

- bearer token required

Request JSON:

```json
{
  "currentPassword": "oldpass123",
  "newPassword": "newpass123"
}
```

Validation rules:

- `currentPassword` required and non-blank
- `newPassword` required and non-blank
- `newPassword` minimum length is 6

Behavior rules:

- authenticated user must exist and not be suspended
- compare `currentPassword` against stored BCrypt hash
- if valid, replace stored password with BCrypt hash of `newPassword`
- set `updated_at = SYSDATETIMEOFFSET()`

Success:

- HTTP `200`
- body:

```json
{
  "message": "Password changed successfully"
}
```

Failure matrix:

- HTTP `401`
  - `Access token required`
  - `Current password is incorrect`
- HTTP `403`
  - `Invalid or expired token`
- HTTP `404`
  - `User not found`
  - `Endpoint not found`

### 8. `DELETE /api/auth/account`

Deletes the authenticated account.

Auth:

- bearer token required

Behavior rules:

- authenticated user must exist and not be suspended
- delete user by `id`

Success:

- HTTP `200`
- body:

```json
{
  "message": "Account deleted successfully"
}
```

Failure matrix:

- HTTP `401`
  - `Access token required`
- HTTP `403`
  - `Invalid or expired token`
- HTTP `404`
  - `User not found`
  - `Endpoint not found`

### 9. `GET /access-check`

Unauthenticated availability probe.

Success:

- HTTP `204`
- no response body

### 10. `GET /api/health`

Unauthenticated health endpoint.

Success:

- HTTP `200`
- body:

```json
{
  "status": "OK",
  "timestamp": "2026-03-15T22:00:00Z"
}
```

## Common Error Contract

All structured API errors must use:

```json
{
  "error": "<message>"
}
```

Unhandled server errors must use:

```json
{
  "error": "Something went wrong!"
}
```

## Authentication Specification

### Bearer token format

- header: `Authorization: Bearer <jwt>`

### JWT claims

The JWT must include these claims:

- `id`
- `username`
- `email`

The JWT subject must be:

- string version of `id`

The token must include:

- issued-at timestamp
- expiration timestamp

### JWT signing

- algorithm: HMAC using the configured symmetric secret
- secret source: base64-decoded value of `app.jwt.secret`
- configuration default maps to env `JWT_SECRET_BASE64`

### Token lifetime

- configured in hours
- default: `24`

## Security Rules

Security must be stateless.

Routes that must be public:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/activate/**`
- `GET /api/health`
- `GET /access-check`

All other routes must require authentication.

Missing token handling:

- HTTP `401`
- `{"error":"Access token required"}`

Invalid/expired token handling:

- HTTP `403`
- `{"error":"Invalid or expired token"}`

## Request Filter Pipeline

Required filter order:

1. rate limiting filter
2. suspended network filter
3. JWT authentication filter within Spring Security before username/password auth filter

### Rate limiting filter

Scope:

- all routes

Storage:

- in-memory only

Key:

- request remote address

Default limits:

- `100` requests
- `15` minutes

Exceeded limit response:

- HTTP `429`
- body:

```json
{
  "error": "Too many requests"
}
```

### Suspended network filter

Scope:

- all routes

Behavior:

- resolve client IP metadata
- if a user exists with `suspended = 1` and matching `ip4` or `ip6`, block the request

Blocked response:

- HTTP `404`
- body:

```json
{
  "error": "Endpoint not found"
}
```

This filter applies even to public endpoints.

### JWT authentication filter

Behavior:

- inspect `Authorization` header
- if bearer token exists:
  - parse JWT
  - construct authenticated principal with `id`, `username`, `email`
  - put it into the Spring Security context
- if parsing fails:
  - return HTTP `403`
  - `{"error":"Invalid or expired token"}`

If no bearer token is present, the filter must not reject the request directly; standard security rules handle that later.

## Client Network Metadata Specification

The rebuild must preserve the current IP resolution behavior.

Resolve IP from first non-blank source in this order:

1. first entry of `X-Forwarded-For`
2. `X-Real-IP`
3. servlet `remoteAddr`
4. fallback literal `unknown`

Resolve user agent from:

- `User-Agent`
- fallback empty string

Derived fields:

- `rawIp`
- `ip4`
- `ip6`
- `agent`

Rules:

- if no usable IP, return `rawIp = "unknown"`, `ip4 = ""`, `ip6 = ""`
- if IP is standard IPv4:
  - `rawIp = ip`
  - `ip4 = ip`
  - `ip6 = ""`
- if IP is plain IPv6:
  - `rawIp = lowercase(ip)`
  - `ip4 = ""`
  - `ip6 = lowercase(ip)`
- if IP is IPv4-mapped IPv6 like `::ffff:127.0.0.1`:
  - `rawIp = 127.0.0.1`
  - `ip4 = 127.0.0.1`
  - `ip6 = ::ffff:127.0.0.1`

## Persistence Specification

### Primary table

- `users`

### Required SQL Server schema

```sql
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
```

### Required indexes

```sql
CREATE INDEX IX_users_ip4 ON users (ip4);
CREATE INDEX IX_users_ip6 ON users (ip6);
CREATE INDEX IX_users_confirmation_token ON users (confirmation_token);
CREATE INDEX IX_users_suspended_ip4 ON users (suspended, ip4);
CREATE INDEX IX_users_suspended_ip6 ON users (suspended, ip6);
```

### Required repository capabilities

The persistence layer must support:

- find user by email or username
- find user by id
- find user by confirmation token
- find user by network (`ip4` or `ip6`)
- find suspended user by network (`ip4` or `ip6`)
- insert user with all registration and metadata fields
- activate user and clear token
- update username/email
- update password
- update `last_visit`
- delete user by id

## Schema Bootstrap Requirements

The service must be able to start against a database that may already contain an older `users` table.

At startup, schema bootstrap logic must:

- create `users` if absent
- add missing columns if absent:
  - `ip4`
  - `ip6`
  - `titul`
  - `last_visit`
  - `question`
  - `answer`
  - `cell`
  - `suspended`
  - `agent`
  - `confirmed`
  - `confirmation_token`
  - `created_at`
  - `updated_at`

Legacy migration rule:

- if legacy column `registration_ip` exists
- and `ip4` and `ip6` are both empty or null
- backfill `ip4`/`ip6` from `registration_ip`

The manual reset script must exist at:

- `server/src/main/resources/recreate-database.sql`

## Email Specification

Activation email requirements:

- sender from configured `app.mail.from`
- recipient is the registered email address
- subject exactly: `Activate your FishFind account`
- HTML body must include:
  - greeting with username
  - notice that account was created
  - activation link

Activation URL format:

- `{frontendBaseUrl}/activate/{activationToken}`

If SMTP send fails, log the failure and raise:

- `Account created in database, but sending activation email failed`

## DTO Specification

### RegisterRequest

Fields:

- `username: String`
- `email: String`
- `password: String`
- `titul: String | null`
- `question: String | null`
- `answer: String | null`
- `cell: String | null`

### LoginRequest

Fields:

- `login: String`
- `password: String`

JSON alias:

- `email`
- `username`

### UpdateProfileRequest

Fields:

- `username: String`
- `email: String`

### ChangePasswordRequest

Fields:

- `currentPassword: String`
- `newPassword: String`

### UserResponse

Fields:

- `id: Long`
- `username: String`
- `email: String`
- `titul: String`
- `cell: String`
- `question: String`
- `answer: String`
- `lastVisit: OffsetDateTime | null`
- `suspended: boolean`
- `createdAt: OffsetDateTime`
- `updatedAt: OffsetDateTime`

### MessageResponse

Fields:

- `message: String`

### LoginResponse

Fields:

- `message: String`
- `token: String`
- `user: UserResponse`

### UserWrapper

Fields:

- `user: UserResponse`

### ErrorResponse

Fields:

- `error: String`

### HealthResponse

Fields:

- `status: String`
- `timestamp: OffsetDateTime`

## Domain Model Specification

The persisted user model must include:

- `id`
- `username`
- `email`
- `password`
- `ip4`
- `ip6`
- `titul`
- `lastVisit`
- `question`
- `answer`
- `cell`
- `suspended`
- `agent`
- `confirmed`
- `confirmationToken`
- `createdAt`
- `updatedAt`

## Configuration Specification

### Server

- `PORT`, default `3000`

### Datasource

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

Default URL:

- `jdbc:sqlserver://tcp:localhost:1433;databaseName=mydb;encrypt=true;trustServerCertificate=true`

### JWT

- `JWT_SECRET_BASE64`
- `JWT_EXPIRATION_HOURS`, default `24`

### Frontend and email

- `FRONTEND_BASE_URL`, default `http://localhost:8080`
- `MAIL_FROM`
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_USER`
- `SMTP_PASS`
- `SMTP_STARTTLS`

### Rate limiting

- `RATE_LIMIT_MAX_REQUESTS`, default `100`
- `RATE_LIMIT_WINDOW_MINUTES`, default `15`

## Known Non-Implemented Features

These are intentionally not part of the rebuilt target unless separately requested:

- profile updates for `titul`, `cell`, `question`, `answer`
- admin endpoints for suspending/unsuspending users
- persistent or distributed rate limiting
- detailed request logging equivalent to the original Express sample
- refresh tokens
- password reset flows

## Acceptance Checklist

The rebuilt service is considered correct only if all of the following hold:

1. A new unconfirmed user can register and receives an activation email.
2. A second registration from the same normalized `ip4` or `ip6` is rejected with HTTP `403`.
3. Activation clears `confirmation_token` and sets `confirmed = 1`.
4. Login fails for unknown, unconfirmed, suspended, and wrong-password cases with the exact status/message mapping above.
5. Successful login returns a JWT and updates `last_visit`.
6. `validate` and `profile` return the persisted user payload, including optional metadata fields.
7. `profile` update changes only username/email.
8. `change-password` requires the correct current password.
9. `account` deletion removes the user row.
10. Missing bearer token returns `401`, invalid token returns `403`.
11. A suspended network is blocked with `404` on both public and protected routes.
12. `/access-check` returns `204`.
13. `/api/health` returns `200` with `status = OK`.
14. The database can be recreated from `recreate-database.sql`.
15. Startup against a partially old schema adds missing columns without failing.

## Source Priority

If a future implementation disagrees with this document, this specification should be treated as the intended target unless it is explicitly superseded.
