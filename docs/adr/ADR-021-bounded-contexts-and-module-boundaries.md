# ADR-021: Bounded contexts and module boundaries

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backend, ddd, modules, architecture

## Context

ADR-003 splits the backend business logic into **one NestJS module per domain** in `packages/core`, each exposing a service and owning its tables, and states that "the details of the boundary rules will be specified in a dedicated ADR". This is that ADR. It must be settled before scaffolding `apps/` and `packages/`, because it decides the folders, the allowed imports, the database schemas and how the rules are checked.

Inputs from previous ADRs:
- tables and their owning module (ADR-017, ADR-019);
- jobs and queues (ADR-011, ADR-019), realtime events (ADR-010), analytics events (ADR-015);
- apps contain only entry points: controllers (`api`), gateways (`realtime`), processors (`worker`) (ADR-003);
- `realtime` never accesses the database (ADR-010); the backoffice only talks to the API (ADR-004).

Taking ADR-017's module list as is creates a **dependency cycle**: `activities` needs the follow graph (`social`) to apply the `followers` visibility, and kudos and comments (`social`) need `activities` to check that the target activity exists and is visible to the user.

## Decision

### 1. Modules of `packages/core`

Two kinds of modules:
- **domain modules**: own tables, carry business rules;
- **platform modules**: wrap an external service, own no table, contain no business rule.

| Module | Kind | Tables owned | Responsibility |
|---|---|---|---|
| `auth` | domain | `user`, `session`, `account`, `verification` | Better Auth configuration, sessions, `role` (admin guard) |
| `users` | domain | `user_profile` | Profile, units, default visibility, privacy zone radius, health data |
| `sports` | domain | `sport_type` | Reference data (populated by migration), per-sport rules |
| `social` | domain | `follow` | Follow graph: follow, accept, unfollow, "does A follow B", followee lists |
| `activities` | domain | `activity`, `activity_stats`, `activity_track`, `activity_attachment`, `activity_import` (*amended by ADR-028*) | Creation, upload, processing, visibility, feed, file import |
| `engagement` | domain | `kudos`, `comment` | Kudos and comments on activities |
| `itineraries` | domain | `itinerary`, `itinerary_waypoint`, `itinerary_leg` (*amended by [ADR-030](ADR-030-itineraries-on-ios.md)*) | Planned Itineraries: Waypoints, Legs, metrics |
| `segments` | domain | `segment`, `segment_effort` | Segments, matching, leaderboards |
| `subscriptions` | domain | `user_subscription`, `revenuecat_event` | Premium status, RevenueCat sync |
| `analytics` | platform | — | `posthog-node` wrapper, typed event catalog (ADR-015) |
| `storage` | platform | — | S3 client on OVH: pre-signed URLs, `HEAD`, reading raw traces (ADR-009) |
| `elevation` | platform | — | Altitudes for a list of points: IGN RGE ALTI, Open-Meteo fallback outside France (*amended by [ADR-030](ADR-030-itineraries-on-ios.md)*) |
| `realtime` | platform | — | **Realtime bridge** (§4): the only listener that forwards selected domain events to Redis for the `realtime` gateway, through the `packages/realtime` publisher (ADR-010) |

**Amendment to ADR-017**: `kudos` and `comment` move from `social` to the new `engagement` module; `social` keeps only `follow`. This breaks the cycle described above. ADR-017's "Tables per module" table is updated accordingly.

Not a module:
- **admin**: administration endpoints live in `apps/api` (`/v1/admin/...`) and call the services of the relevant modules (e.g. `activities.reprocess`). There is no admin module with its own rules.

### 2. Allowed dependencies between modules

A module may call **only the modules listed in its row**, and only through their exported service. The graph is acyclic and layered:

| Layer | Module | May depend on |
|---|---|---|
| 0 | `auth`, `users`, `sports`, `subscriptions` | — |
| 1 | `social` | `users` |
| 1 | `itineraries` | `sports`, `users` (*amended by [ADR-030](ADR-030-itineraries-on-ios.md)*) |
| 2 | `activities` | `sports`, `users`, `social` |
| 3 | `engagement` | `activities`, `social`, `users` |
| 3 | `segments` | `activities`, `sports` |
| any | every domain module | `analytics`, `storage` (platform modules), `packages/db`, `packages/contracts`. *Amended by [ADR-030](ADR-030-itineraries-on-ios.md)*: also the `elevation` platform module and `packages/geo` (`@repo/geo`: pure distance, resampling, elevation gain and polyline functions, moved out of `activities/domain`) |

Domain modules never import `packages/realtime` nor the `realtime` platform module: they emit domain events, and the bridge decides what reaches the mobile app (§3).

Rules:
1. **A module never calls a module of a higher layer.** To react to something that happens higher up, it listens to a **domain event** or processes a **job** (§3).
2. **Chaining jobs is done by the worker**, not by modules: for example, `ProcessActivityProcessor` enqueues `match-segments` after `activities` returns successfully. `activities` does not know `segments` exists.
3. **Modules may enqueue jobs** (producer) using the job schemas of `packages/contracts`; **only `apps/worker` contains processors**.
4. **Domain events and analytics events** are emitted by the module service, **after the transaction commit** (ADR-011). Realtime messages to the mobile app are never published by a domain module: they come from the bridge (§3).
5. **Cross-module references are identifiers only** (`userId`, `activityId`): no module returns another module's Drizzle entities.
6. **Reading another module's data goes through its service, in batch**: services expose methods that take a list of identifiers (e.g. `users.getSummaries(userIds)`, `engagement.getCounts(activityIds)`). A list screen then costs one query per module, not one per row (§6).
7. **Deleting a user account** (GDPR) cascades through foreign keys in the database; any cleanup outside the database (bucket objects, RevenueCat) will be a dedicated job, to be specified when account deletion is built.

### 3. Cross-module reactions: domain events or jobs

When something happens in one module and another module must react, there are two mechanisms, chosen by one question: **if the reaction is lost, is anything permanently wrong?**

| | **Domain event** (in-process bus) | **Job** (BullMQ) |
|---|---|---|
| Tool | `@nestjs/event-emitter` | BullMQ queue (ADR-011) |
| Delivery | Immediate, in the same process | Through Redis, possibly another process |
| If the process restarts at the wrong time | **Reaction lost** | Job kept in Redis, run later |
| Retries | None | Yes, with backoff |
| Use when | The reaction is **disposable or recomputable**: losing it leaves nothing permanently wrong | The reaction **must happen**: its loss would leave data wrong |
| Examples | Realtime push to the mobile app (through the bridge), cache invalidation, "convenience" automations (e.g. pre-filling data the user can also trigger by hand) | Track processing, segment matching, subscription sync, anything that writes a persisted fact another module relies on |

**Domain event rules:**
- **Typed contracts**: event names (`{module}.{entity}.{verb}` in the past tense, e.g. `activities.activity.processed`) and payloads (Zod schema + TypeScript type) are defined in `packages/contracts`, not in the emitting module. A listener in a lower layer imports the contract, not the higher module, so the dependency rules of §2 still hold.
- **Minimal payload**: identifiers and what the listeners need (`activityId`, `userId`, `status`), never whole entities. A listener that needs more reads it through the owning module's service.
- **Emitted after the commit**, never inside a transaction: a listener must never see a fact that could still be rolled back.
- **Asynchronous listeners** (`@OnEvent(name, { async: true })`): the emitter does not wait for them, a slow listener never slows down a request or a job.
- **Listeners never throw**: each one catches its errors and logs them (`warn`); a listener failure never fails the emitter.
- **Listeners are idempotent**: before acting they check whether the work is already done, so a duplicated or replayed event has no side effect.
- **A listener never writes a fact that cannot be recomputed.** Counters and aggregates are computed on read (e.g. `count(kudos)` in `engagement.getCounts`) or written in the same transaction as the fact they count.
- **Same process only**: an event emitted in `worker` is handled in `worker`. To reach another backend process, use a job; to reach the mobile app, the realtime bridge.

**Job rules (reactions that must happen):**
- The use case that commits the fact **enqueues the job itself**, right after the commit, with a job ID derived from the entity (ADR-011). A listener does not enqueue must-happen jobs: the event could be lost between the commit and the enqueue.
- The small window between commit and enqueue (process crash) is covered by a **recurring reconciliation job** that finds entities left in an intermediate state, as for activities stuck in `processing` (ADR-019 §7). Each must-happen flow defines its own reconciliation.

### 4. Realtime bridge (amends ADR-010)

Domain modules do not publish to Redis. They emit domain events; the `realtime` platform module owns **the only listener** that forwards them to the `realtime` gateway:

```
activities (worker, after commit)
  └─ emit('activities.activity.processed', { activityId, userId, status })
        │  in-process bus
        ▼
realtime platform module · RealtimeBridge (@OnEvent, async)
  ├─ looks up the event in its forwarding table
  ├─ computes topics (userTopic(userId)) and the mobile payload
  └─ publishRealtimeEvent(...) from packages/realtime ──► Redis `realtime:events` ──► gateway ──► iPhone
```

Rules:
- **Explicit forwarding table** (allow-list) in the bridge: domain event → mobile event type, topics, payload. An event absent from the table never reaches a client. This is the single place to review what leaves the backend and to whom (privacy).
- **Mobile event names stay those of ADR-010** (`activity.processed`, `activity.failed`, `activity.segments_matched`): the bridge maps internal names to the public protocol, so internal refactoring never breaks the app.
- **Fire-and-forget**: a Redis failure is logged and ignored, consistent with ADR-010's at-most-once delivery and the mobile resync on reconnection.
- **Loaded in `api` and `worker`**: both processes emit events that may concern the mobile app, so both import the `realtime` platform module.
- **Testable**: the bridge is tested alone (event in → expected publish out); domain modules are tested without Redis.

### 5. Jobs and events per module

| Module | Queue · job | Domain events forwarded to the mobile app by the bridge | Analytics events |
|---|---|---|---|
| `activities` | `activities` · `process-activity`, recurring reconciliation (ADR-019 §7); `imports` · `import-activity` (*amended by [ADR-028](ADR-028-activity-import-from-file.md)*); `activities` · `reprocess-activity` (*amended by [ADR-033](ADR-033-activity-detail-edit-delete.md)*) | `activities.activity.processed` → `activity.processed`, `activities.activity.failed` → `activity.failed`, `activities.import.completed` → `activity_import.completed`, `activities.import.failed` → `activity_import.failed`; *amended by [ADR-033](ADR-033-activity-detail-edit-delete.md)*: `activities.activity.updated` → `activity.updated`, `activities.activity.deleted` → `activity.deleted` | `activity_processed`, `activity_failed`, `activity_imported`, `activity_import_failed` |
| `itineraries` (*amended by [ADR-030](ADR-030-itineraries-on-ios.md)*) | — | `itineraries.itinerary.saved` → `itinerary.saved`, `itineraries.itinerary.deleted` → `itinerary.deleted` | `itinerary_created`, `itinerary_updated`, `itinerary_renamed`, `itinerary_deleted`, `itinerary_save_failed` |
| `engagement` (*amended by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)*) | — | `engagement.comment.added` → `comment.created`, `engagement.comment.edited` → `comment.updated`, `engagement.comment.deleted` → `comment.deleted`, `engagement.kudos.given` / `removed` → `kudos.changed` (topic `activity:{id}`) | — |
| `segments` | `segments` · `match-segments` | `segments.efforts.matched` → `activity.segments_matched` | — |
| `subscriptions` | `subscriptions` · `sync-subscription` | — | `subscription_*` (ADR-014) |
| later | `media` (thumbnails), `notifications` (APNs) | — | — |

The queue name is the name of the module that owns the processing logic. Domain events are added as needs appear, following §3.

### 6. Internal structure of a module

```
packages/core/src/<module>/
├── <module>.module.ts        Nest module: providers, exports only the service
├── <module>.service.ts       public facade: the only class other modules and apps call
├── use-cases/                one file per use case (e.g. complete-activity.use-case.ts)
├── domain/                   pure functions and types, no Nest, Drizzle or I/O
│                             (e.g. compute-metrics.ts, apply-privacy-zone.ts)
├── listeners/                domain event listeners (§3), if any
├── repositories/             Drizzle queries on the module's own tables only
└── index.ts                  public API: module, service, public types
```

Supporting files elsewhere:
- Drizzle schema: `packages/db/src/schema/<module>.ts` (ADR-017).
- Contracts: `packages/contracts/src/<module>/` (API DTOs, job payloads, domain events, analytics events).

Rules:
- **`domain/` is pure**: unit-testable without a database (metrics, privacy zone, segment matching geometry, premium status computation).
- **Repositories only touch the module's own tables**, for reading and writing. No SQL join across modules.
- **List screens compose batch calls.** Example, the feed of 20 activities:
  1. `social.getFolloweeIds(userId)`;
  2. `activities` reads the page of activities of those users (its own tables);
  3. `users.getSummaries(authorIds)` for names and avatars;
  4. `engagement.getCounts(activityIds)` for kudos and comments.

  Four queries whatever the page size, and each module keeps full control of its tables.

  *Amended by [ADR-029](ADR-029-activity-feed-and-card.md)*: steps 1–2 run in `activities` (`getFeedPage`), steps 3–4 in `apps/api` (`FeedAssembler`), since `activities` may not call `engagement`. Step 3 also reads `auth.getPublicIdentities` as a name/avatar fallback, plus `engagement.getKudoedBy` for the viewer's kudos. A `geocoding` platform module (Mapbox reverse geocoding) joins `analytics` and `storage`.
- **Public API = `index.ts`**. `packages/core` exposes one subpath per module (`@repo/core/activities`, …) in its `package.json` `exports`; internals are not exported.

### 7. One PostgreSQL schema per domain module

Each domain module owns a **PostgreSQL schema with the same name**, holding exactly the tables listed in §1. Platform modules have no schema.

`public` is the **shared kernel**: it only holds tables imposed by a library or genuinely shared by several modules, each with an explicit justification. Today that is only Better Auth (`auth` module), kept exactly as in the Better Auth documentation.

```
public         Better Auth tables of the auth module (user, session, account, verification)
               + PostGIS extension (geometry types, ST_* functions)
users          user_profile
sports         sport_type
social         follow
activities     activity, activity_stats, activity_track, activity_attachment
engagement     kudos, comment
itineraries    itinerary, itinerary_waypoint, itinerary_leg   (added by ADR-030)
segments       segment, segment_effort
subscriptions  user_subscription, revenuecat_event
```

Rules:
- **Drizzle**: each `packages/db/src/schema/<module>.ts` declares its schema with `pgSchema('<module>')` and creates its tables on it (e.g. `activitiesSchema.table('activity', …)`). `auth.ts` uses the default `pgTable`, as generated by Better Auth.
- **Foreign keys across schemas are allowed** and kept (e.g. `activities.activity.user_id` → `public.user.id`): referential integrity stays in the database.
- **Always qualified**: application tables are always referenced with their schema (`activities.activity`, `public.user`), in Drizzle (through `pgSchema`) and in any raw SQL. The `search_path` stays at its default (`public`) and is only relied on for PostGIS types and `ST_*` functions.
- **New table in `public`** only with a written justification (imposed by a library, or used by 2+ modules); when in doubt, it goes in the module's schema.
- **Migrations**: `drizzle-kit generate` reads the schema files (`packages/db/src/schema/*.ts`) and emits the `CREATE SCHEMA` statements itself; nothing to maintain by hand. `schemaFilter` is only relevant for `push`/`pull` (introspection), which the project does not use: schema changes always go through generated migrations.
- **Later, optional**: one PostgreSQL role per app with grants per schema, so that the database itself refuses a write outside the owning module. Not in the MVP: the three backend apps share one role.

### 8. Which app uses which module

| App | May import | Role |
|---|---|---|
| `apps/api` | all modules (via `index.ts`, including the `realtime` bridge), `contracts` | Controllers, Better Auth mount, admin endpoints |
| `apps/worker` | all modules (via `index.ts`, including the `realtime` bridge), `contracts` | Processors, job chaining |
| `apps/realtime` | `packages/realtime`, `contracts` only | No `core`, no `db` (ADR-010); token checked without calling the API |
| `apps/admin` | `packages/contracts`, `packages/ui` | No `core`, no `db` (ADR-004) |
| any app | never another app | ADR-005 |

### 9. Automatic enforcement

The rules are checked by tools that do not depend on the linter, so they hold whatever linter the project uses (ESLint from the Turborepo template, Biome, or none):

1. **Package `exports`**: `@repo/core/<module>` subpaths only. Importing a module's internals from an app fails at compile time (TypeScript).
2. **`dependency-cruiser`**, one configuration at the repository root, run as a Turborepo task (`turbo check-deps`):
   - modules: a module is imported only through its `index.ts`, and only by the modules allowed in §2 (allow-list);
   - `domain/` may not import `@nestjs/*`, `drizzle-orm` or `repositories/`;
   - only the `realtime` platform module may import the `packages/realtime` publisher;
   - apps: the matrix of §8 (e.g. `apps/realtime` may not import `@repo/core` or `@repo/db`);
   - no cycles.
3. **CI**: the task fails on any violation, so the rules are checked on every pull request and not only in code review. When setting it up, one deliberately forbidden import is written to check that the rule really fails.

This replaces the `eslint-plugin-boundaries` option mentioned in ADR-003. The exact configuration is written when scaffolding `packages/core`; this ADR only fixes the rules it must encode.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Keep `kudos` and `comment` in `social` (ADR-017 as is) | Cycle `social` ↔ `activities` |
| Move `kudos` and `comment` into `activities` | `activities` is already the largest module (upload, processing, feed); engagement rules (moderation, counters, notifications later) would make it grow further |
| Visibility check in the `api` controller, calling both modules | Business rule leaks into the app; `worker` and future endpoints would have to repeat it |
| Jobs only, no event bus | A job for every small reaction (cache, push, convenience automation) costs Redis round trips, retries and monitoring for nothing |
| Listeners that enqueue must-happen jobs | The event can be lost between commit and enqueue; the use case enqueues directly, backed by a reconciliation job |
| Transactional outbox (events written in the same transaction, relayed by a poller) | The textbook guarantee, but a table, a relay and cleanup to operate; reconciliation jobs cover the MVP flows. To reconsider if many must-happen reactions appear |
| Domain modules publish realtime messages themselves (ADR-010 as is) | Every module knows Redis, topics and the mobile protocol; no single place to review what is sent to clients |
| Event bus only, no jobs | A lost event would leave data permanently wrong for reactions that must happen (processing, segments, subscriptions) |
| Read-only SQL joins across modules for list screens (`*.query.ts`) | Couples a module to other modules' schemas; batch service calls give the same performance with a constant number of queries |
| DDD layout suggested by tooling (`src/<context>/domain/{entities,value-objects,...}` at the repository root) | Contradicts the monorepo layout (ADR-005) and the NestJS module shape of ADR-003; too many folders for the MVP size |
| One package per module (`packages/core-activities`, …) | Strongest isolation, but many packages to build and version; subpath exports plus dependency-cruiser give enough isolation |
| `eslint-plugin-boundaries` | Ties the rules to ESLint and needs per-package path settings in a pnpm monorepo; dependency-cruiser checks the whole repository from one configuration |
| All tables in `public`, ownership by file convention only | Ownership invisible in the database; no way to restrict writes per module later |
| Better Auth tables in an `auth` schema | Not the documented setup; its schema generator targets the default schema. Keeping them in `public` costs nothing |
| One database per module | Loses foreign keys and transactions across modules; heavier to operate on a single VPS |

## Consequences

### Positive
- Acyclic, layered module graph: each module can be understood and tested with only the layers below it.
- Each module fully owns its tables: no SQL outside the module touches them.
- Lightweight reactions use a simple in-process event bus; reactions that must happen keep the guarantees of BullMQ, backed by reconciliation.
- Domain modules know nothing about Redis, topics or the mobile protocol: the realtime bridge is the single, reviewable place that decides what reaches clients.
- The scaffold of `packages/core`, `packages/db` and `packages/contracts` follows directly from §1, §6 and §7.
- Boundaries are checked by the compiler and dependency-cruiser, independently of the linter choice.
- Table ownership is visible in the database itself (one schema per module).

### Negative / Risks
- **Batch methods to write**: each service needs `getMany`-style methods for list screens; a little more code than a single SQL join.
- **Feed by followee identifiers**: `social.getFolloweeIds` then `where user_id in (...)` is fine for the MVP; a user following thousands of people would need another approach (materialized feed), to be reconsidered then.
- **Choosing event vs job** is a judgment call on each new reaction; the question of §3 ("is anything permanently wrong if it is lost?") must be asked in review.
- **dependency-cruiser setup**: path aliases and pnpm workspace resolution to configure once when scaffolding.
- **Forwarding table to maintain**: a new mobile event means an entry in the bridge; forgetting it means the app is not notified (it still resyncs through the API).
- **Reconciliation per must-happen flow**: each such flow needs its own recurring check, written together with the flow.

## References
- [ADR-003: Backend stack and architecture](ADR-003-backend.md)
- [ADR-017: MVP data model](ADR-017-data-model.md)
- [ADR-019: Activity creation flow](ADR-019-activity-creation-flow.md)
- NestJS modules: https://docs.nestjs.com/modules
- NestJS events (`@nestjs/event-emitter`): https://docs.nestjs.com/techniques/events
- dependency-cruiser: https://github.com/sverweij/dependency-cruiser
- Transactional outbox pattern: https://microservices.io/patterns/data/transactional-outbox.html
- Drizzle `pgSchema`: https://orm.drizzle.team/docs/schemas
- Node.js package subpath exports: https://nodejs.org/api/packages.html#subpath-exports

## Links

- **Details**: [ADR-003](ADR-003-backend.md) (dedicated ADR for module boundary rules; replaces the `eslint-plugin-boundaries` option)
- **Amends**: [ADR-017](ADR-017-data-model.md) (`kudos` and `comment` move to the new `engagement` module; one PostgreSQL schema per module), [ADR-010](ADR-010-backend-realtime.md) (realtime messages published by a single bridge listener, not by domain modules)
- **Amended by**: [ADR-028](ADR-028-activity-import-from-file.md) (`activity_import` table, `imports` queue, `activities.import.*` events in the bridge table), [ADR-029](ADR-029-activity-feed-and-card.md) (feed assembly in `apps/api`, `geocoding` platform module), [ADR-030](ADR-030-itineraries-on-ios.md) (`itineraries` domain module, `elevation` platform module, `@repo/geo` package, `itinerary.*` events in the bridge table), [ADR-033](ADR-033-activity-detail-edit-delete.md) (`reprocess-activity` job, `activities.activity.updated` / `deleted` in the bridge table), [ADR-034](ADR-034-activity-engagement-and-live-detail.md) (`engagement` events in the bridge table)
- **Related**: [ADR-004](ADR-004-backoffice.md), [ADR-005](ADR-005-monorepo.md), [ADR-009](ADR-009-backend-api.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-015](ADR-015-posthog.md), [ADR-019](ADR-019-activity-creation-flow.md), [ADR-023](ADR-023-transactional-email-resend.md) (`notifications` platform module)
