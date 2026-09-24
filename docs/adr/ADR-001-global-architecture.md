# ADR-001: Global architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: architecture, api, async, realtime
- **Source**: Like-Strava architecture deck, slide 08 "Global architecture" (and slide 10 for the flow example)

## Context

Like-Strava is a Strava clone. The platform must:
- receive sports activities recorded on mobile (GPS traces that are sometimes large);
- compute the **official values** of an activity (distance, time, elevation gain, route, privacy zone), which is computationally expensive;
- notify the mobile app in real time when processing is finished;
- provide a backoffice to administer the platform;
- protect the data: a client must never be able to bypass the business rules.

## Decision

**Clients go through the API, heavy processing is asynchronous.**

### Components

| Component | Technology | Role |
|---|---|---|
| Mobile app | Swift + SwiftUI | Recording and viewing activities |
| Backoffice | Next.js | Platform administration |
| API | NestJS (REST) | Single entry point for clients: business rules, database writes, job enqueueing, pre-signed URLs |
| WS server | NestJS (WebSocket) | Pushes events to the mobile app |
| Worker | NestJS + BullMQ | Runs heavy processing (e.g. `process-activity`) |
| Redis | Redis | Job queues (BullMQ) and Pub/Sub between worker, API and WS server |
| Database | PostgreSQL + PostGIS | Business and geospatial data |
| Object storage | OVH S3 bucket | Raw traces and media |

### Flow

```
 Backoffice ──JSON/HTTP──┐
                         ▼
 Mobile app ──JSON/HTTP──► NestJS api ──write──► PostgreSQL + PostGIS
   │  ▲   │                 │    │                        ▲
   │  │   │                 │    └─pre-signed URL─┐       │ write
   │  │   └──direct PUT/GET─┼──────────────► S3 bucket    │
   │  │                     │ enqueue / pub       ▲       │
   │  │                     ▼                     │ GET   │
   │  │                   Redis ──jobs──────► Worker ─────┘
   │  │                     ▲  ◄──pub "job done"───┘
   │  │                     │ sub
   │  └──────WSS──────── NestJS WS
```

### Principles

1. **Clients only talk to the API** (JSON/HTTP) for data. They never contact PostgreSQL or Redis.
2. **Only the API and the worker write to the database.** The WS server only relays events.
3. **Heavy processing is asynchronous**: the API records the request, enqueues a job and responds immediately (`202 Accepted`). The worker runs the job outside the API.
4. **Large files do not go through the API**: the API issues a pre-signed URL, and the client uploads to or downloads from the bucket directly.
5. **Real time goes through Redis**: the worker publishes an event (e.g. `activity.processed`), the WS server is subscribed to it and pushes it to the mobile app over WSS. The event is a **signal with minimal content**: the mobile app then reloads the data through the API, which remains the single source of truth (ADR-010).
6. **The backoffice does not use real time**: it is connected only to the API.

### Example: creating an activity (slide 10, detailed in a dedicated ADR)

1. The mobile app creates the activity (`POST /activities`, status `pending`) and receives a pre-signed URL.
2. It uploads the compressed trace directly to the bucket, then calls `POST /activities/:id/complete`.
3. The API moves the activity to `processing`, enqueues `process-activity` and responds `202`.
4. The worker reads the trace, computes the metrics and the route, writes the result in a transaction (`processed`), then publishes `activity.processed`.
5. The WS server pushes the event to the mobile app, which reloads the activity through the API and displays the official values.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Synchronous processing in the API | The API would stay blocked during computations, long and unpredictable response times for the mobile app, no retries |
| Uploading traces through the API | Unnecessary network and memory load on the API, when the bucket can receive files directly |
| Mobile polling instead of WebSocket | Unnecessary repeated requests, delay in displaying the official values |
| Direct client access to the database (e.g. a BaaS such as Supabase) | Business rules can be bypassed, logic split between clients and database policies |
| Microservices per domain | Disproportionate operational cost for the size of the project (see ADR-003) |

## Consequences

### Positive
- The API stays fast: it only validates, records and enqueues.
- The worker and the WS server scale independently of the API.
- Business and access rules are centralized on the server side.
- Failed processing can be replayed (BullMQ retries) without client involvement.

### Negative / Risks
- **Redis is critical**: it carries the queues and the Pub/Sub. Plan for persistence (AOF) and monitoring.
- **Missed WS push**: if the mobile app is not connected when the event occurs, it must fetch the activity state through the API on reconnection. The WS is an optimization, not the source of truth.
- **Eventual consistency**: between `processing` and `processed`, the displayed values are provisional (computed locally by the mobile app).
- **Processing failures**: the `failed` status exists in the model, but the policy (number of attempts, mobile notification) remains to be defined in the ADR on the activity creation flow.
- **More components to operate**: API, WS, worker, Redis, PostgreSQL, bucket.

## References
- Like-Strava architecture deck, slides 08 and 10
- [ADR-002: Mobile](ADR-002-mobile.md)
- [ADR-003: Backend](ADR-003-backend.md)
- [ADR-004: Backoffice](ADR-004-backoffice.md)
- [ADR-005: Monorepo](ADR-005-monorepo.md)

## Links

- **Detailed by**: [ADR-002](ADR-002-mobile.md), [ADR-003](ADR-003-backend.md), [ADR-004](ADR-004-backoffice.md), [ADR-005](ADR-005-monorepo.md)
