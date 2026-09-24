# ADR-011: Backend · `worker` app (BullMQ jobs)

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backend, worker, bullmq, jobs

## Context

The worker runs the heavy processing that the API puts in a queue (ADR-001). The first job is `process-activity` (slide 10): read the activity, the profile and the sport type, download the raw track, clean the points, compute the metrics, build the route, apply the privacy zone, write the result in a transaction, then publish `activity.processed`.

## Decision

### Stack

| Component | Choice | Role |
|---|---|---|
| Framework | **NestJS** as an **application context** (no HTTP server) | BullMQ processors |
| Queues | **BullMQ** (`@nestjs/bullmq`), **consumer** | Job execution |
| Bucket | **AWS SDK v3** on the OVH endpoint | Reading raw tracks |
| Subscriptions | **RevenueCat** REST API | Full state of a subscriber (ADR-014) |
| Analytics | `posthog-node`, via the `analytics` module of `packages/core` | Server events (`activity_processed`, `subscription_*`, ADR-015) |
| Database | Drizzle (`packages/db`), PostGIS | Reads and writes in a transaction |
| Business logic | Modules of `packages/core` | Same rules as the API |
| Redis | `ioredis` | Publishing real-time events via the `packages/realtime` publisher (ADR-010) |
| Foundation | Pino, Zod-validated configuration, Zod contracts (ADR-009) | — |

### Jobs

| Queue | Job | Triggered by | MVP |
|---|---|---|---|
| `activities` | `process-activity` | `POST /activities/:id/complete` | Yes |
| `segments` | `match-segments` (segment efforts) | End of `process-activity` | Yes, separate job (ADR-019) |
| `subscriptions` | `sync-subscription`: reads the subscriber state via the RevenueCat REST API, updates the premium status in the database, sends the event to PostHog (ADR-014) | RevenueCat webhook received by the API | Yes, as soon as subscriptions exist |
| `media` | map thumbnail generation | End of `process-activity` | Later |
| `notifications` | APNs delivery | Business events | **Later** (no Apple Developer account yet) |

### Principles

1. **Processors are thin**: they validate the job data with the Zod schema from `contracts`, then call the service of the relevant module in `packages/core`. No business rules in the processor.
2. **Idempotent jobs**:
   - the job ID is derived from the entity (e.g. `process-activity:{activityId}`), which prevents duplicates in the queue;
   - a replayed job does not create duplicates in the database, thanks to the transaction and "upsert" writes.
3. **Retries**: several attempts with exponential backoff for technical errors (database, bucket, Redis). Invalid data (unreadable track) is a permanent failure, with no retry.
4. **Permanent failure**: the activity moves to `failed` and an `activity.failed` event is published. Policy set in ADR-019: 5 attempts with exponential backoff for technical errors, immediate permanent failure for an invalid track, `processing_error` and `processing_attempts` columns, retry from the backoffice.
5. **Publish after commit**: the event (`activity.processed`, topic `user:{userId}`) is only published once the transaction is committed, so a result that is not in the database is never announced. Its payload is minimal (`activityId`, `status`): the mobile app reloads the activity through the API (ADR-010).
6. **Concurrency set per queue**: CPU jobs (track processing) have limited concurrency; we add worker instances rather than increase the concurrency of a single one.
7. **Graceful shutdown**: on shutdown, the worker finishes its in-progress jobs before exiting, so deployments do not interrupt processing.
8. **Correlation**: the `requestId` received in the job data (ADR-009) is added to all the job's logs and to published events.

### Monitoring

- Pino logs per job (start, end, duration, error).
- Failed jobs remain viewable in Redis (`removeOnFail` limited, not immediate).
- A dashboard (e.g. Bull Board) may be exposed later, protected, or failed jobs shown in the backoffice via the API.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Run jobs in the API | Contrary to the goal: the API must stay lightweight (ADR-003) |
| Queue in PostgreSQL (pg-boss, jobs table) | Possible, but Redis is already present and BullMQ handles retries, priorities and concurrency |
| Serverless tasks (Lambda, functions) | Outside the VPS infrastructure, access to the database and bucket more complex |
| Worker without NestJS (Node script) | Loses sharing of `packages/core` modules and dependency injection |

## Consequences

### Positive
- Heavy processing affects neither the API nor real-time.
- Same business rules as the API thanks to `packages/core`.
- Automatic retries and recovery in case of a temporary outage.

### Negative / Risks
- **Redis is critical**: a queued job can be lost if Redis goes down without persistence (AOF to enable, ADR-001).
- **Idempotency to test**: every job must be replayable without side effects.
- **Memory**: long tracks (several hours) can be large; process them as streams if necessary.
- **APNs notifications postponed**: they depend on an Apple Developer account (personal or company), not available for now.

## References
- [ADR-001: Global architecture](ADR-001-global-architecture.md)
- [ADR-003: Backend stack and architecture](ADR-003-backend.md)
- [ADR-009: Backend · api app](ADR-009-backend-api.md)
- BullMQ: https://docs.bullmq.io
- NestJS standalone applications: https://docs.nestjs.com/standalone-applications

## Links

- **Details**: [ADR-003](ADR-003-backend.md)
- **Amended by**: [ADR-019](ADR-019-activity-creation-flow.md) (jobs and failure policy)
- **Related**: [ADR-001](ADR-001-global-architecture.md), [ADR-009](ADR-009-backend-api.md) (shared foundation), [ADR-010](ADR-010-backend-realtime.md), [ADR-014](ADR-014-revenuecat.md), [ADR-015](ADR-015-posthog.md)
