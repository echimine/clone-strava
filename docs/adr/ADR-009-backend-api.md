# ADR-009: Backend · `api` app (REST)

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backend, api, nestjs, rest

## Context

ADR-003 splits the backend into three NestJS apps (`api`, `realtime`, `worker`) that share business logic via `packages/core`, `packages/db` and `packages/contracts`. This ADR sets:
- the **common foundation** for the three apps (contracts, validation, logs, configuration), which ADR-010 and ADR-011 refer to;
- the stack specific to the `api` app: the only entry point for clients (mobile and backoffice).

## Decision

### Common foundation for the three backend apps

| Topic | Choice |
|---|---|
| Shared contracts | **Zod**, in `packages/contracts`: API request bodies and responses, job payloads, realtime events |
| Validation in Nest | Zod validation pipe (e.g. `nestjs-zod`): DTOs are derived from the `contracts` schemas, without class-validator |
| Configuration | Environment variables **validated by a Zod schema at startup**: the app refuses to start if a variable is missing |
| Logs | **Pino** via `nestjs-pino`: structured JSON logs on standard output |
| Data access | Drizzle, schema in `packages/db` (ADR-003) |

**Logs, in practice:**
- Each log line is a JSON object (level, message, context, identifiers). On the VPS, Docker collects standard output; a viewing tool can then be plugged in without touching the code.
- Each HTTP request gets a **correlation identifier** (`requestId`). It is copied into job payloads and published events, to follow an activity from the API to the worker and then to the WS server.
- Tokens, passwords and `Authorization` headers are **redacted** automatically (`redact`).
- Error tracking (e.g. Sentry) can be added later.

### `api` app stack

| Building block | Choice | Role |
|---|---|---|
| Framework | **NestJS** (default Express adapter) | REST controllers |
| Authentication | **Better Auth** | Accounts, sessions; bearer token for iOS, cookie for the backoffice |
| Bucket | **AWS SDK v3** (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`) configured on the **OVH Object Storage** endpoint | Pre-signed URLs |
| Job queues | **BullMQ** (`@nestjs/bullmq`), **producer only** | Enqueuing, never execution |
| Redis | `ioredis` client | Publishing realtime events via the `packages/realtime` publisher (ADR-010) |
| Realtime tokens | `jsonwebtoken` (HS256, `REALTIME_TOKEN_SECRET` secret shared with `realtime`) | `POST /v1/realtime/token` endpoint |
| Subscriptions | **RevenueCat** webhook (ADR-014) | `POST /v1/webhooks/revenuecat` endpoint |
| Analytics | `posthog-node`, via the `analytics` module of `packages/core` (ADR-015) | Reliable server-side events |
| Documentation | **OpenAPI generated from the Zod schemas** | API reference and generation of Swift models (ADR-005) |
| Protection | `@nestjs/throttler` (rate limiting); no CORS: the backoffice goes through the Next.js proxy (ADR-013) and the mobile app is not affected by CORS | — |
| Health | `@nestjs/terminus` | `/health` endpoint (database, Redis) for deployment |

### Principles

1. **The API never does heavy processing**: it validates, writes to the database, enqueues and responds (`202 Accepted` for asynchronous processing).
2. **Controllers are thin**: Zod validation, authentication guard, call to the module service (`packages/core`), response formatting.
3. **Authentication**:
   - Better Auth is mounted on `/api/auth/*`;
   - a guard checks the session on all protected routes;
   - an **admin role** guard protects the backoffice endpoints (ADR-004);
   - `GET /v1/me` returns the current user and their role (used by the backoffice to display or deny access, ADR-013).
4. **Realtime token**: `POST /v1/realtime/token`, protected by the session, returns a JWT valid for 60 seconds containing the user and their allowed topics (`user:{userId}` for the MVP). The mobile app uses it to open the WebSocket connection; the gateway verifies it without calling the API (ADR-010).
5. **RevenueCat webhook**: `POST /v1/webhooks/revenuecat`, outside any user session, authenticated by a **secret header** configured in RevenueCat. The API checks the secret, records the event (deduplicated by its identifier), enqueues the `sync-subscription` job and responds `200` immediately (ADR-014).
6. **Private bucket**: no public read. Pre-signed URLs have a short lifetime, and object keys follow a convention, for example `activities/{userId}/{activityId}/trace.json.gz`.
7. **Single error format** for the whole API (code, message, validation details), described in `contracts`.
8. **Versioned routes** (`/v1/...`) so the API can evolve without breaking old versions of the mobile app, which stay installed on phones until the user updates. To avoid having to create a `/v2`:
   - **backward-compatible changes only**: adding a field is allowed; renaming, removing or changing the type of a field is not;
   - **tolerant clients**: the app ignores unknown fields, new fields are optional;
   - **minimum app version**: the API exposes the minimum accepted version; below it, the app asks the user to update. An old API version can thus be retired without waiting indefinitely.

## Alternatives Considered

| Topic | Alternative | Why rejected |
|---|---|---|
| Validation | class-validator + class-transformer | Duplicates the Zod contract schemas, which are already used by the backoffice and the worker |
| Contracts | tRPC / ts-rest | The Swift mobile app cannot benefit from them; REST + OpenAPI stays readable by all clients |
| Logs | Built-in NestJS logger | Unstructured text, hard to filter; no correlation or redaction |
| Logs | Winston | Slower and more verbose to configure than Pino for JSON logs |
| HTTP adapter | Fastify | Faster, but the Better Auth + NestJS integration is simpler with Express; to be reconsidered if performance requires it |
| Bucket | OVH-specific SDK | The standard S3 API via AWS SDK v3 avoids depending on OVH |

## Consequences

### Positive
- A single Zod schema per exchange, used to validate, type (backoffice) and document (OpenAPI → Swift).
- Usable logs from the start, with a common thread from the API to the WS.
- The API stays fast and predictable: no job runs in its process.

### Negative / Risks
- **Zod in NestJS** is not the default path: dependency on an integration library (or a custom pipe), and OpenAPI generation to be verified.
- **Better Auth with NestJS**: no official integration, to be wired and tested (bearer for iOS, cookie for the backoffice).
- **OVH via AWS SDK**: endpoint, region and URL style to configure, and to test on pre-signed URLs.
- **Versioning**: old versions will have to be maintained as long as non-updated mobile apps use them.

## References
- [ADR-003: Backend stack and architecture](ADR-003-backend.md)
- [ADR-005: Monorepo](ADR-005-monorepo.md)
- Zod: https://zod.dev
- nestjs-pino: https://github.com/iamolegga/nestjs-pino
- AWS SDK v3 S3: https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/s3/
- OVHcloud Object Storage (S3): https://help.ovhcloud.com/csm/fr-public-cloud-storage-s3-getting-started
- BullMQ with NestJS: https://docs.nestjs.com/techniques/queues

## Links

- **Details**: [ADR-003](ADR-003-backend.md) (backend stack and architecture)
- **Related**: [ADR-001](ADR-001-global-architecture.md), [ADR-005](ADR-005-monorepo.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-014](ADR-014-revenuecat.md), [ADR-015](ADR-015-posthog.md)
