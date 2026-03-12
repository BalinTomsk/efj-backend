# Auth - Multi-module layout

This version reorganizes the original `auth.zip` service into three Maven modules so the auth functionality can be reused by future proxy services.

## Modules

- `api` - shared contracts, DTOs, paths, and authenticated-user model
- `client` - reusable Java client library built on Spring `RestClient`
- `server` - runnable Spring Boot auth service implementation

## Build

```bash
mvn clean package
```

## Run server

```bash
cd server
mvn spring-boot:run
```

## Use client from another service

Add dependency on:

- `info.fishfind:api:1.0.0`
- `info.fishfind:client:1.0.0`

Then create or inject `AuthClient` and point it to your auth service base URL.
