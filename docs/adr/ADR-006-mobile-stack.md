# ADR-006: Detailed mobile app stack

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: mobile, ios, stack, realtime

## Context

ADR-002 set the main building blocks of the mobile app (Swift + SwiftUI, GRDB, Mapbox). The technical frameworks still need to be chosen for:
- **realtime**: receiving events from the WS server (e.g. official values of a processed activity, ADR-001);
- **GPS recording**, including with the screen locked;
- **connectivity detection**, to know when to sync activities recorded offline;
- local persistence and the map, already chosen.

Guiding principle: **favor Apple's native frameworks** when they cover the need, and limit third-party dependencies to those that bring real value (GRDB, Mapbox).

## Decision

| Need | Choice | Type |
|---|---|---|
| UI | **SwiftUI** | Native |
| REST networking | **URLSession** (async/await) | Native |
| Realtime (app open) | **Native WebSocket**: `URLSessionWebSocketTask` | Native |
| Notifications (app in background or closed) | **APNs** + **UserNotifications** framework | Native |
| Local persistence | **SQLite via GRDB** | Dependency (SPM) |
| Map | **Mapbox Maps SDK for iOS** | Dependency (SPM) |
| Subscriptions | **RevenueCat** (`purchases-ios`), see ADR-014 | Dependency (SPM) |
| Analytics and feature flags | **PostHog** (`posthog-ios`), see ADR-015 | Dependency (SPM) |
| GPS | **Core Location** (`CLLocationManager`) | Native |
| Connectivity | **`NWPathMonitor`** (Network framework) | Native |
| Token storage | **Keychain** | Native |

### Native WebSocket (`URLSessionWebSocketTask`)

- **Opening the connection** (protocol detailed in ADR-010):
  1. the app requests a short-lived realtime token from the API (`POST /v1/realtime/token`, with its session);
  2. it opens `wss://…/ws` with this token in the `Authorization: Bearer` header;
  3. it subscribes to its topic: `{ "a": "sub", "topic": "user:{userId}" }`.
- JSON messages decoded with `Codable`, in the versioned protocol format `{ v, t, id, data }` (ADR-010). A message with an unknown version is ignored.
- The WebSocket client lives in `Core/Network` and exposes events as an `AsyncStream` to the features that subscribe to them.
- What the native API does not do and must be implemented:
  - **heartbeat**: application-level `{ "a": "ping" }` message every 25 seconds (the server replies `pong`) to detect a dead connection;
  - **automatic reconnection** with exponential backoff, **with a new token every time**; reaction depends on the close code (`4001` invalid token, `4008` quota exceeded, `4009` server restart);
  - **deduplication**: an event whose `id` has already been received is ignored;
  - **resynchronization**: after each reconnection, the app queries the API to get the state of activities in `processing`. The WS is never the source of truth (ADR-001).
- The connection is **open in the foreground only**: iOS suspends the app and cuts its sockets shortly after it moves to the background. When returning to the foreground, reconnect then resynchronize.

### Push notifications (APNs)

> **Priority: later.** Decision recorded so it is not forgotten, but it is not an MVP priority. Until APNs is in place, the app fetches state from the API when returning to the foreground.

The WebSocket cannot work when the app is closed or in the background: this is an iOS constraint, not a choice. To notify the user in that case, we use **Apple Push Notifications (APNs)**:

| App state | Channel |
|---|---|
| In the foreground | WebSocket: immediate screen update |
| In the background or closed | APNs: notification displayed by iOS |

- At startup, the app requests authorization (`UNUserNotificationCenter`), registers with APNs (`registerForRemoteNotifications`) and **sends its device token to the API**, associated with the user.
- Notified events (to be refined): **activity processed** (official values available), kudos, comment, follow request.
- When a notification is tapped, the app opens on the relevant screen and reloads data from the API.
- Silent notifications (`content-available`) can be used to refresh data in the background, but iOS throttles them and does not guarantee delivery: they remain a bonus, never the only source.
- **Server-side impact** (to be detailed in the backend stack ADR): device token registration endpoint, devices table (absent from the slide 09 model), sending notifications to APNs from the backend (e.g. a worker job), and choosing WS or APNs depending on whether the user is connected to the `realtime` server.

### SQLite with GRDB

- `DatabasePool` (WAL mode): concurrent reads while GPS points are being written.
- Versioned schema with `DatabaseMigrator`.
- `ValueObservation` to feed SwiftUI stores when data changes.
- Main local tables: activities, GPS points of the ongoing recording, **sync queue** (pending uploads to the API and the bucket).

### Mapbox Maps SDK for iOS

- Installed via Swift Package Manager.
- Route display (`LineLayer` on a GeoJSON source), custom styles, offline maps (`OfflineManager` / `TileStore`).
- Mapbox types stay in the presentation layer: the domain uses its own coordinate types (ADR-002).

### Core Location for GPS

- `CLLocationManager` with an `activityType` suited to the sport (`.fitness`, `.otherNavigation`…) and `desiredAccuracy = kCLLocationAccuracyBest` during recording.
- **Background recording**: `location` mode in `UIBackgroundModes`, `allowsBackgroundLocationUpdates = true`, visible location indicator (`showsBackgroundLocationIndicator`).
- "While Using the App" authorization is sufficient if recording starts in the foreground; the `NSLocationWhenInUseUsageDescription` strings (and `NSLocationAlwaysAndWhenInUseUsageDescription` if needed) explain the usage.
- Each point is written to GRDB immediately, so nothing is lost if the app is killed.
- The GPS service is isolated behind a protocol of the `Recording` domain: it can be replaced by a fake location provider in tests and in the simulator.

### `NWPathMonitor` for connectivity

- A single monitor in `Core/Network`, which publishes the state (`satisfied`, `unsatisfied`, expensive interface or not) as an `AsyncStream` or observable state.
- Used to:
  - **trigger the sync queue** when the connection comes back;
  - display an "offline" indicator;
  - avoid sending heavy traces over an expensive or constrained connection (`isExpensive`, `isConstrained`), depending on preferences.
- **Accepted limitation**: `NWPathMonitor` indicates that a network route exists, not that the API is reachable (captive portal, server down). Sync therefore also handles real network failures with retries; the monitor is only a trigger.

## Alternatives Considered

| Topic | Alternative | Why rejected |
|---|---|---|
| WebSocket | Starscream, Socket.IO client | Unnecessary dependency: `URLSessionWebSocketTask` covers the need; Socket.IO would also impose a specific protocol on the server side |
| WebSocket | Polling the API | Repeated requests, display delay |
| Notifications | Keeping the WebSocket open in the background | Impossible on iOS: the app is suspended |
| Notifications | Third-party service (Firebase Cloud Messaging, OneSignal) | Unnecessary intermediary for an iOS-only app; direct APNs is enough |
| REST networking | Alamofire | URLSession + async/await is enough |
| Persistence | Core Data / SwiftData | Less SQL control over large volumes of GPS points, less predictable migrations |
| Persistence | Raw SQLite (C API) | Too low-level: no migrations, observation or mapping |
| Map | MapKit | Limited style customization, no heatmap, no real offline maps (ADR-002) |
| Connectivity | Reachability (SCNetworkReachability) | Old API, replaced by `NWPathMonitor` |
| Connectivity | Pinging the API regularly | Consumes battery and data; real failures are already handled by sync |

## Consequences

### Positive
- Only **four third-party dependencies** (GRDB, Mapbox, RevenueCat, PostHog), each isolated behind a protocol; everything else is native and follows iOS versions.
- Reliable recording: points written as they come, recovery possible after the app stops.
- Sync triggered automatically when the network comes back.

### Negative / Risks
- **Native WebSocket**: heartbeat, reconnection and resynchronization must be written and tested ourselves.
- **Two realtime channels to maintain** (WS and APNs), and on the server side logic to choose which one to use and avoid duplicates.
- **APNs**: Apple Developer account, APNs authentication key (`.p8`) to store as a server-side secret, handling of invalid tokens (uninstalled device). The user can refuse notifications: the app must work without them.
- **Battery**: high-accuracy GPS is costly. Tune `distanceFilter` and accuracy per sport, and stop updates as soon as recording ends.
- **App Store review**: background location usage must be clearly justified.
- **`NWPathMonitor` can be wrong** (network present but API unreachable): never rely on it alone.
- **Minimum iOS version** to be set (iOS 17 considered for the Observation framework) in the ADR on the detailed mobile architecture.

## References
- [ADR-001: Global architecture](ADR-001-global-architecture.md)
- [ADR-002: Mobile stack and architecture](ADR-002-mobile.md)
- URLSessionWebSocketTask: https://developer.apple.com/documentation/foundation/urlsessionwebsockettask
- Core Location: https://developer.apple.com/documentation/corelocation
- NWPathMonitor: https://developer.apple.com/documentation/network/nwpathmonitor
- GRDB.swift: https://github.com/groue/GRDB.swift
- Mapbox Maps SDK for iOS: https://docs.mapbox.com/ios/maps/

## Links

- **Details**: [ADR-002](ADR-002-mobile.md) (mobile stack and architecture)
- **Related**: [ADR-001](ADR-001-global-architecture.md), [ADR-010](ADR-010-backend-realtime.md) (realtime protocol), [ADR-014](ADR-014-revenuecat.md) (subscriptions), [ADR-015](ADR-015-posthog.md) (analytics)
