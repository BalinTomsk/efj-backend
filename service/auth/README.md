# FishFind Auth Service (Spring Boot + MSSQL)

This project is a Java 21 / Spring Boot  
- registration with bcrypt password hashing
- email activation using a UUID token
- login with JWT
- token validation
- profile read/update
- password change
- account delete
- `/api/health`
- rate limiting, helmet/cors equivalents
- SQLite storage

This Spring Boot version keeps the same endpoint family but replaces SQLite with **external Microsoft SQL Server**.

## Stack

- Java 22
- Spring Boot 3.x
- Spring Web
- Spring Security
- Spring JDBC
- MSSQL JDBC Driver
- Java Mail Sender
- JJWT

## Endpoints

- `POST /api/auth/register`
- `GET /api/auth/activate/{activationToken}`
- `POST /api/auth/login`
- `GET /api/auth/validate`
- `GET /api/auth/profile`
- `PUT /api/auth/profile`
- `PUT /api/auth/change-password`
- `DELETE /api/auth/account`
- `GET /api/health`

## MSSQL setup

Create a database, then run:

```sql
src/main/resources/schema.sql
```

```bash
mvn spring-boot:run
```

Or package:

```bash
mvn clean package
java -jar target/fishfind-auth-service-1.0.0.jar
```

## Notes

- JWT secret must be base64-encoded and at least 32 bytes after decoding.
- This project uses Spring JDBC rather than JPA, which keeps it closer to the original simple SQL-based backend.
- The simple in-memory rate limiter is fine for a single instance. For multi-node production, move rate limiting to API Gateway, Redis, or a distributed filter.
- CORS is open by default for easier local integration. Tighten it for production.
