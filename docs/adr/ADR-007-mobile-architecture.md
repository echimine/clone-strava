# ADR-007: Detailed mobile app architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: mobile, ios, architecture, hexagonal
- **Source**: Like-Strava architecture deck, slide 02 "Mobile architecture · features + hexagonal"

## Context

ADR-002 sets the principle (split by feature, hexagonal, View → Store → Service → UseCase → Repository flow) and ADR-006 sets the tools (URLSession, native WebSocket, GRDB, Mapbox, Core Location, `NWPathMonitor`). What remains is to define **how the code is organized and wired together**: the exact role of each layer, where the technical building blocks live, dependency injection, concurrency and tests.

Offline operation and sync are covered by a separate ADR (ADR-008).

## Decision

### Directory tree

```
MyApp/
├── App/
│   ├── StravaCloneApp.swift        entry point
│   └── Di.swift                    composition root: creates and wires all dependencies
├── Core/
│   ├── Domain/                     shared types (identifiers, coordinates, units, errors)
│   ├── Database/                   AppDatabase (GRDB DatabasePool), migrations
│   ├── Network/
│   │   ├── APIClient               URLSession, JSON encoding, normalized errors
│   │   ├── AuthSession             Better Auth token, stored in the Keychain
│   │   ├── WebSocketClient         URLSessionWebSocketTask, heartbeat, reconnection
│   │   └── ConnectivityMonitor     NWPathMonitor
│   └── DesignSystem/               colors, typography, reusable SwiftUI components
└── Features/
    ├── Recording/
    │   ├── Domain/                 entities + protocols (repositories; LocationProvider moved to Core/Domain by ADR-027)
    │   ├── Application/            services + use cases
    │   ├── Infrastructure/         implementations: GRDB, API, Core Location
    │   └── Presentation/           stores + views (Mapbox only here)
    ├── Feed/
    ├── Profile/
    ├── Segments/
    └── Auth/
```

### Role of each layer

| Layer | Role | Forbidden |
|---|---|---|
| **View** (SwiftUI) | Displays the store state, forwards user intents | Calling a service, a use case or a repository |
| **Store** (`@Observable`, `@MainActor`) | Screen state, intent methods (`start()`, `refresh()`…), handling of loading and displayable errors | Direct access to GRDB, URLSession or Core Location |
| **Service** | Coordinates over time: GPS stream, timer, several use cases (e.g. `RecordingService`) | Depending on SwiftUI |
| **UseCase** | One business action, one rule (e.g. `StartRecording`, `FinishRecording`, `LoadFeed`) | Depending on a concrete implementation |
| **Repository** (protocol in `Domain/`) | Data access port | — |
| **Repository** (implementation in `Infrastructure/`) | Concrete adapter: GRDB, APIClient | Containing business rules |

Trivial use cases are accepted to keep a uniform flow.

### Dependency rules

1. `Domain/` depends only on the Swift standard library and `Core/Domain`: no SwiftUI, GRDB, Mapbox or Core Location.
2. `Application/` depends on `Domain/` only.
3. `Infrastructure/` implements the protocols of `Domain/` and uses `Core/Database` and `Core/Network`.
4. `Presentation/` depends on `Application/` and `Core/DesignSystem`, never on `Infrastructure/`.
5. **A feature does not import another feature.** Anything shared moves up into `Core/`.
6. **Mapbox types stay in `Presentation/`**: conversion from domain coordinates happens at display time. *Amended by [ADR-027](ADR-027-user-location-on-maps.md)*: `Core/DesignSystem/Map/` (shared `AppMap` component and `MapboxLocationBridge`) is presentation code too and may import Mapbox.

### Location of the technical building blocks (ADR-006)

| Building block | Location | Exposed to features through |
|---|---|---|
| APIClient, AuthSession | `Core/Network` | Used by the `Infrastructure/` repositories |
| WebSocketClient | `Core/Network` | `AsyncStream` of typed events, filtered by feature |
| ConnectivityMonitor | `Core/Network` | Observable state + `AsyncStream` |
| GRDB database | `Core/Database` | GRDB repositories of each feature; each feature declares its migrations |
| GPS (Core Location) | ~~`Features/Recording/Infrastructure`~~ `Core/Location` *(Amended by [ADR-027](ADR-027-user-location-on-maps.md))* | Multi-subscriber `LocationProvider` protocol in `Core/Domain`, shared by Map and Recording; `LocationPermissionService` via `environment` |
| Local Activities and their upload | `Core/LocalActivities` *(Amended by [ADR-031](ADR-031-live-recording-on-ios.md))* | Local Activity, points and Pauses (GRDB), Save transaction, trace v2 builder, `ActivitySender`; written by Recording, read by Feed, driven by a queue coordinator in `App/` |
| Routing (Mapbox Directions) | `Core/Routing` *(Amended by [ADR-031](ADR-031-live-recording-on-ios.md))* | `MapboxDirectionsRouter`, `RoutingProfile`, `RetryBackoff`, used by Itineraries and Recording; the Itinerary cache is read through a protocol in `Core/Domain` |
| Live Activity | widget extension target *(Amended by [ADR-031](ADR-031-live-recording-on-ios.md))* | `ActivityAttributes` type compiled into the app and the extension; ActivityKit adapter behind a port in `Features/Recording` |

### Dependency injection

- **Initializer injection**, with no framework and no global singleton.
- `App/Di.swift` creates the shared objects (database, APIClient, WebSocketClient, ConnectivityMonitor) then, for each feature, its repositories, use cases and services.
- Each feature exposes a **factory** that builds its stores; views receive it through the SwiftUI environment.
- In tests and previews, fakes are plugged in (in-memory repositories, simulated `LocationProvider`).

### Concurrency and state

- **Swift Concurrency** (`async/await`, `AsyncStream`, actors) everywhere; no Combine.
- **Swift 6 mode** (strict concurrency checking) enabled from the start.
- Stores annotated `@MainActor`; services that handle shared state (e.g. GPS point buffer) are **actors**.
- **Observation** framework (`@Observable`) for stores, which sets the **minimum version to iOS 17**.

### Modularization

- **At first: a single Xcode target**, with the tree above. Dependency rules are checked in code review.
- **Later**, if the rules drift: extraction into local Swift packages (`Core`, one package per feature), so the compiler enforces them.

### Tests

| Target | Tool | Approach |
|---|---|---|
| Domain, use cases, services | Swift Testing | Fake repositories and fake `LocationProvider` |
| GRDB repositories | Swift Testing | In-memory SQLite database, real migrations |
| API repositories | Swift Testing | Mocked `URLProtocol` |
| Stores | Swift Testing | Mocked services and use cases, state assertions |
| Critical flows (recording) | XCUITest | A few scenarios, simulated GPS |

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Simple MVVM (View + ViewModel + global services) | Business logic scattered across ViewModels, strong coupling to GRDB and the API |
| TCA (The Composable Architecture) | Heavy dependency, learning curve, boilerplate |
| Injection framework (Swinject, Factory) | Initializer injection is enough and stays compiler-checked |
| Combine for streams | Swift Concurrency is the recommended model and integrates with Observation |
| Swift packages per feature from the start | High setup cost while features are still changing a lot |
| iOS 16 minimum | Would require `ObservableObject`/Combine; iOS 17 covers the vast majority of active devices |

## Consequences

### Positive
- Business logic (recording calculations, rules) is tested without UI, database or network.
- GRDB, the API, Mapbox or Core Location can change without touching the domain.
- Each feature is read and modified in a single folder.
- Swift 6 detects concurrency errors at compile time, which matters with GPS and WebSocket running in parallel.

### Negative / Risks
- **Verbosity**: protocols, use cases, factories and entity ↔ persistence model mappings.
- **Rules not enforced by the compiler** as long as we stay on a single target.
- **Strict Swift 6**: some APIs (Core Location, Mapbox) will need adaptations (`@preconcurrency`, explicit isolation).
- **iOS 17 minimum**: devices stuck on iOS 16 will not be able to install the app.

## References
- Like-Strava architecture deck, slide 02
- [ADR-002: Mobile stack and architecture](ADR-002-mobile.md)
- [ADR-006: Detailed mobile stack](ADR-006-mobile-stack.md)
- [ADR-008: Mobile offline and sync](ADR-008-mobile-offline-sync.md)
- Observation: https://developer.apple.com/documentation/observation
- Swift Testing: https://developer.apple.com/documentation/testing

## Links

- **Details**: [ADR-002](ADR-002-mobile.md) (principles), [ADR-006](ADR-006-mobile-stack.md) (detailed stack)
- **Related**: [ADR-008](ADR-008-mobile-offline-sync.md) (offline and sync)
- **Amended by**: [ADR-027](ADR-027-user-location-on-maps.md) (GPS moved to `Core/Location`; Mapbox allowed in `Core/DesignSystem/Map/`)
- **Amended by**: [ADR-031](ADR-031-live-recording-on-ios.md) (`Core/LocalActivities`, `Core/Routing`, widget extension for the Live Activity)
