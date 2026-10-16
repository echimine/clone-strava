# ADR-010: Backend · `realtime` app (WebSocket gateway)

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: backend, realtime, websocket, redis

## Context

The `realtime` server notifies the mobile app when something changes on the server side (e.g. an activity processed by the worker, ADR-001). Constraints:
- the mobile app uses the **native WebSocket** `URLSessionWebSocketTask` (ADR-006): standard WebSocket protocol, with no extra layer;
- the mobile app already works by **resynchronizing through the API** each time it returns to the foreground and on each reconnection (ADR-008): realtime is a convenience, not the source of truth;
- the service must be able to run as **multiple instances** and be redeployed without impacting the API.

## Decision

### 1. A gateway that only does transport

`apps/realtime` **authenticates, holds connections and routes events by topic**. It contains no business rules, **does not access the database** and does not call the API. All logic stays in the API and the worker.

### 2. Stack

| Building block | Choice |
|---|---|
| Framework | **NestJS** (HTTP only for `/health`) |
| WebSocket | **`ws`** library, `WebSocketServer({ noServer: true })` hooked to the `upgrade` event of Nest's HTTP server, path **`/ws`** |
| Tokens | **HS256** JWT (`jsonwebtoken`), verified locally |
| Redis | `ioredis`, dedicated connection in subscriber mode |
| Protocol | `packages/realtime` (Zod schemas, see §8) |
| Foundation | Pino, configuration validated by Zod (ADR-009) |

We do not use the `@nestjs/platform-ws` adapter: handling the `upgrade` ourselves makes it possible to **reject an invalid token with a `401` before opening the WebSocket connection**.

### 3. Authentication with a short-lived token

1. The mobile app requests a token from the API: `POST /v1/realtime/token`, authenticated by its Better Auth session (ADR-009).
2. The API returns a JWT signed with `REALTIME_TOKEN_SECRET`, valid for **60 seconds**, containing: the user (`sub`), the **allowed topics**, the issuer (`iss: clone-strava-api`) and the audience (`aud: clone-strava-realtime`).
3. The mobile app opens `wss://…/ws` with `Authorization: Bearer <token>`.
4. The gateway verifies **locally** the signature, algorithm, issuer, audience and expiration. No network call. Invalid token = `401` and connection refused.
5. The token is only used for opening: the connection stays valid after it expires. **Each reconnection requests a new token.** A revoked session therefore cannot reconnect beyond 60 seconds.

*Amended by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)* (§5): a topic that is not in the token can be added on an open connection with a **subscription grant**: `POST /v1/realtime/grants { topic }` checks that the user may receive that topic and returns a 60 s HS256 JWT `{ sub, topic }` with audience `clone-strava-realtime-grant`, verified locally by the gateway like the token.

Any connection that presents an `Origin` header (browser) is refused: the backoffice does not use realtime (ADR-001).

### 4. Topics and explicit subscription

- The client subscribes after connecting: `{ "a": "sub", "topic": "user:123" }`.
- The gateway only accepts topics **present in the token**; otherwise it responds `sub:err` (`forbidden`). *Amended by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)*: or a topic covered by a valid grant sent with the subscription (`{ "a": "sub", "topic": "activity:42", "grant": "…" }`), whose `sub` matches the connection's user.
- MVP topics:

| Topic | Recipient | Example events |
|---|---|---|
| `user:{userId}` | The user themselves, on all their devices | `activity.processed`, `activity.failed` (*amended by [ADR-030](ADR-030-itineraries-on-ios.md)*: also `itinerary.saved`, `itinerary.deleted`; *amended by [ADR-033](ADR-033-activity-detail-edit-delete.md)*: also `activity.updated`, `activity.deleted`) |
| `activity:{activityId}` (*added by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)*) | Anyone who can see the Activity, while its detail is open (grant) | `comment.created`, `comment.updated`, `comment.deleted`, `kudos.changed`, `activity.updated`, `activity.deleted` |

- Later, other topics can be added (e.g. `activity:{id}` for live comments) without changing the architecture. *Amended by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)*: `activity:{id}` is added, through subscription grants.

### 5. Protocol (versioned)

**Event, server → client:**

```json
{ "v": 1, "t": "activity.processed", "id": "evt_…", "data": { "activityId": "…", "status": "processed", "at": "2026-09-24T10:00:00Z" } }
```

- `v`: protocol version; a client that receives an unknown version ignores the message.
- `t`: event type, in `{resource}.{verb}` format. *Amended by [ADR-028](ADR-028-activity-import-from-file.md)*: `activity_import.completed` and `activity_import.failed` are added for file imports.
- `id`: unique identifier, to ignore a duplicate on the client side.
- `data`: **minimal content**. The resource data is never sent: the client reloads through the API (`GET /v1/activities/:id`). The API remains the single source of truth, and it is the same code as resynchronization (ADR-008).

**Control:**

| Direction | Messages |
|---|---|
| Client → server | `{a:"sub", topic}` (*amended by [ADR-034](ADR-034-activity-engagement-and-live-detail.md)*: optional `grant`), `{a:"unsub", topic}`, `{a:"ping"}` |
| Server → client | `{a:"sub:ok", topic}`, `{a:"sub:err", topic, reason: "forbidden" \| "limit"}`, `{a:"pong"}` |

**Close codes:**

| Code | Meaning | Client reaction |
|---|---|---|
| `4001` | Invalid or expired token detected after opening | New token, then reconnection |
| `4008` | Message quota exceeded | Reconnection with backoff |
| `4009` | Server shutdown (deployment) | Immediate reconnection |

An unreadable or unknown message is **ignored** (never an exception), but counted toward the quota.

### 6. Broadcasting via Redis

- A **single channel**: `realtime:events`.
- The API or the worker publishes `{ "topics": ["user:123"], "envelope": { … } }`. **Topics are computed by the publisher**: the gateway has nothing to decide.
- *Amended by [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md)*: inside `api` and `worker`, only the **realtime bridge** (the `realtime` platform module of `packages/core`) publishes. Domain modules emit internal domain events; the bridge maps them, through an explicit allow-list, to the mobile event types, topics and payloads of this ADR.
- Each gateway instance is subscribed to the channel and sends the envelope to local connections subscribed to those topics (in-memory registry `topic → connections`).
- Multiple instances possible, without sticky sessions.
- The event source is behind an interface: replaceable by a fake in tests.

### 7. Delivery: at most once

- No persisted queue, no catch-up: an event emitted while the mobile app is disconnected is lost.
- This is accepted: on each connection or reconnection, the mobile app reloads state through the API (ADR-008).

### 8. Shared package `packages/realtime`

With no dependency on NestJS, used by `api`, `worker` and `realtime`:
- Zod schemas for the envelope, control messages and the message published on Redis;
- close codes, Redis channel name, protocol version;
- topic naming functions (`userTopic(userId)`);
- per-topic connection registry (used by `realtime`);
- a **publisher** (`publishRealtimeEvent(topics, type, data)`) used by the API and the worker, which builds the envelope (with `id` and `v`) and publishes on Redis. *Amended by [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md)*: called only by the realtime bridge, never directly by domain modules.

This package is added to those listed in ADR-005.

### 9. Protection and robustness

- **Per-connection quotas**: maximum number of topics, maximum number of messages over a time window (exceeded → close `4008`), maximum message size (`maxPayload`).
- **Heartbeat**: the client sends an application-level `ping` every **25 seconds**; the server closes silent connections.
- **Graceful shutdown**: on `SIGTERM`, all connections are closed with `4009` before stopping (Nest shutdown hooks).
- **Health**: `GET /health` (Redis reachable, number of connections).
- VPS **reverse proxy** configured for the WebSocket `upgrade` and long timeouts.

### 10. Tests

- Unit: message encoding/decoding, token verification, quotas.
- Integration: opening with a valid and an invalid token, rejection of an unauthorized topic, broadcasting an event to **two instances** via Redis, `4009` close on shutdown.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Socket.IO | Proprietary protocol, incompatible with the native iOS WebSocket |
| `@nestjs/platform-ws` adapter | Less control over connection opening (rejection before `upgrade`) |
| Checking the Better Auth session on each connection (database read or API call) | Coupling to the API or the database, latency on each connection; the short-lived token avoids both |
| Sending the official values in the event | Two data sources for the mobile app; reloading through the API keeps a single path |
| Automatic subscription on connection | Less extensible: explicit subscription allows adding topics without changing the protocol |
| Redis Streams with catch-up of missed events | Unnecessary as long as the mobile app resynchronizes through the API |
| Managed service (Pusher, Ably) | SaaS dependency and cost, for a simple need |

## Consequences

### Positive
- Directly compatible with `URLSessionWebSocketTask`, with no dependency on the iOS side.
- Gateway with no database and no business logic: simple, testable, easy to scale out.
- No network request to authenticate a connection.
- Adding an event type or a topic requires no architecture change.

### Negative / Risks
- **Plumbing to write**: registry, quotas, heartbeat, graceful shutdown.
- **Shared secret** `REALTIME_TOKEN_SECRET` between `api` and `realtime`: to be stored as a secret, rotated if compromised.
- **Lost events** if the mobile app is disconnected (accepted, ADR-008).
- **One more request** on each connection (token, then activity reload): negligible.

### For later
- **Presence**: Redis "user connected" marker set by the gateway, so the worker can choose between WebSocket and APNs notification (ADR-006, ADR-011).

## References
- [ADR-006: Detailed mobile stack](ADR-006-mobile-stack.md)
- [ADR-008: Mobile offline and sync](ADR-008-mobile-offline-sync.md)
- [ADR-009: Backend · api app](ADR-009-backend-api.md)
- ws: https://github.com/websockets/ws
- RFC 6455 (WebSocket): https://www.rfc-editor.org/rfc/rfc6455

## Links

- **Details**: [ADR-003](ADR-003-backend.md)
- **Amends**: [ADR-005](ADR-005-monorepo.md) (adds `packages/realtime`)
- **Amended by**: [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (single realtime bridge in `api` and `worker`), [ADR-028](ADR-028-activity-import-from-file.md) (`activity_import.*` events), [ADR-030](ADR-030-itineraries-on-ios.md) (`itinerary.*` events), [ADR-033](ADR-033-activity-detail-edit-delete.md) (`activity.updated`, `activity.deleted`), [ADR-034](ADR-034-activity-engagement-and-live-detail.md) (§3 subscription grants, §4 `activity:{id}` topic, §5 `sub` with `grant`, comment and kudos events)
- **Related**: [ADR-001](ADR-001-global-architecture.md), [ADR-006](ADR-006-mobile-stack.md), [ADR-008](ADR-008-mobile-offline-sync.md), [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md)
