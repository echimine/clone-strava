# ADR-003: Backend stack and architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backend, nestjs, modular-monolith, postgis
- **Source**: Like-Strava architecture deck, slides 03 "Stack · backend", 04 "Backend architecture · modular monolith", 07 "Monorepo", 08 "Global architecture"

## Context

The backend carries the business rules and protects the data (ADR-001). It is made up of three roles:
- **api**: REST endpoints for the mobile app and the backoffice;
- **realtime**: WebSocket server that pushes events to the mobile app;
- **worker**: runs heavy jobs.

The goal is that **the API never runs a job**: it only enqueues them. However, the worker contains real business logic (slide 10: reading the activity, the profile and the sport type, computing metrics, building the route, privacy zone, writing statistics). The API and the worker therefore need **the same business rules, the same database schema and the same contracts**.

## Decision

### Stack

| Building block | Choice | Role |
|---|---|---|
| Framework | **NestJS** | The three apps: api, realtime, worker |
| Database | **PostgreSQL + PostGIS** | Relational and geospatial data |
| Data access | **Drizzle ORM** | Typed schema, queries, migrations |
| Messaging | **Redis** | Pub/Sub between worker, api and realtime |
| Asynchronous tasks | **BullMQ** (on Redis) | Queues and jobs, retries, backoff |
| Object storage | **OVH Object Storage bucket** (S3-compatible) | Raw traces and media, pre-signed URLs |
| Authentication | **Better Auth** | Accounts, sessions, OAuth; bearer token for iOS |

### Three NestJS apps, shared business logic

```
apps/
├── api/        REST controllers + Better Auth → enqueues jobs, never runs them
├── realtime/   WebSocket gateways → subscribes to Redis, checks the session, pushes to mobile
└── worker/     BullMQ processors → runs jobs by calling the shared business logic
packages/
├── db/         Drizzle schema, client, migrations
├── core/       Nest business modules: service + use cases + repository (no controller)
└── contracts/  Zod schemas: API DTOs, job data, real-time events
```

- Each app **contains only its entry points** (controllers, gateways or processors) and imports the business modules from `packages/core`.
- The three apps are **deployed and scaled separately**.
- The **shared contracts** (`packages/contracts`) guarantee that the API and the worker agree on the job format, and that the worker and the WS server agree on the event format.

### Modular monolith

The business logic is split into **one module per domain** (activities, users, social, segments, auth…). Each module exposes a **service** and owns its tables. Flow of a request or a job:

```
Controller (api) / Processor (worker) → Service → Use case → Repository → PostgreSQL
```

A module calls another module only through its exported service. Cross-domain reactions preferably go through jobs or events. The details of the boundary rules will be specified in a dedicated ADR.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Each app writes its own business logic**, only the schema and contracts are shared | Independent apps | Duplicated rules that diverge (e.g. different distance computation between api and worker) | Rejected |
| **Worker and realtime call the API over HTTP** | No shared code | The worker loads the API on every job, which is exactly what we want to avoid | Rejected |
| **A single NestJS app with 3 entry points** | The simplest, processes still separated | No clear separation of apps in the monorepo | Rejected |
| **Microservices per domain** | Full independence | Operational cost, distributed transactions | Rejected |
| **Shared internal packages** (`core`, `db`, `contracts`) | A single version of the rules, separate apps | Build configuration for Nest packages | **Chosen** |

Other stack choices rejected: plain Express/Fastify (no modular structure), MongoDB (weaker geospatial and relational support), Prisma (limited PostGIS support), Auth0/Clerk (SaaS dependency, data outside our database), disk storage on the VPS.

## Consequences

### Positive
- The API stays light and fast; heavy computations run in the worker.
- A single implementation of the business rules, used by the API and the worker.
- The whole backend is in TypeScript: types shared with the backoffice.
- PostGIS natively covers the geospatial needs (routes, segments, search by area).

### Negative / Risks
- **Building internal packages**: `packages/core` uses NestJS decorators, so it needs a suitable TypeScript and Turborepo configuration (compiled packages, build order).
- **Boundaries not enforced by the compiler**: plan ESLint rules (`eslint-plugin-boundaries`) to forbid internal imports between modules.
- **PostGIS with Drizzle**: custom geometry types and raw SQL for spatial queries, GiST indexes in the migrations.
- **Better Auth**: no official NestJS integration and no iOS SDK. To be wired in the api (and session verification in realtime); tokens managed on the Swift side (Keychain).
- **Redis is critical** (see ADR-001).

## References
- Like-Strava architecture deck, slides 03, 04, 07, 08
- [ADR-001: Global architecture](ADR-001-global-architecture.md)
- [ADR-005: Monorepo](ADR-005-monorepo.md)
- NestJS: https://docs.nestjs.com
- Drizzle ORM: https://orm.drizzle.team
- BullMQ: https://docs.bullmq.io
- Better Auth: https://www.better-auth.com

## Links

- **Depends on**: [ADR-001](ADR-001-global-architecture.md)
- **Related**: [ADR-005](ADR-005-monorepo.md)
