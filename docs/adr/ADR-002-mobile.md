# ADR-002: Mobile application stack and architecture

- **Status**: accepted
- **Date**: 2026-09-24
- **Deciders**: echimine
- **Tags**: mobile, ios, mapbox, offline
- **Source**: Like-Strava architecture deck, slides 01 "Stack · mobile application" and 02 "Mobile architecture · features + hexagonal"

## Context

The mobile app records activities (continuous GPS tracking, including in the background), stores them on the device to work without a network, sends them to the platform (ADR-001) and displays them on a map (routes, courses, eventually heatmaps). The target is **iOS only**.

## Decision

### Stack

| Building block | Choice | Role |
|---|---|---|
| Language / UI | **Swift + SwiftUI** | Native iOS application |
| Local persistence | **GRDB** (SQLite) | Activities, GPS points, sync queue (offline-first) |
| Mapping | **Mapbox Maps SDK for iOS** | Maps, routes, courses |
| Geolocation | Core Location | GPS recording, independent of the map provider |

**Mapbox instead of MapKit** (the architecture deck planned MapKit):
- customizable map styles (Mapbox Studio: dark background, terrain, trails, cycle paths);
- data-driven layers (`LineLayer`, `HeatmapLayer`) suited to long routes and future heatmaps;
- terrain and 3D, useful for trail running and cycling;
- offline maps (`OfflineManager` / `TileStore`), consistent with the offline-first approach.

### Architecture: features + hexagonal

```
MyApp/
├── App/          entry point + dependency composition (Di.swift)
├── Core/         Domain (shared types), Database, Network (APIClient, auth, WebSocket), DesignSystem
└── Features/     Recording, Feed, Profile, Segments, Auth
    └── <Feature>/  Domain / Application / Infrastructure / Presentation
```

Flow of a user action:

```
SwiftUI View → Store → Service → UseCase → Repository → local SQLite / API
```

Principles:
- **One folder per feature**, each feature split into hexagonal layers; the business logic (`Domain/`) depends on neither SwiftUI, GRDB nor Mapbox.
- **A feature does not import another feature**: whatever is shared moves up into `Core/`.
- Concrete implementations are wired in `App/Di.swift`.

### Communication with the platform (ADR-001)

- **REST** to the API for all data.
- **Direct upload to the S3 bucket** for traces and media, via pre-signed URLs provided by the API.
- **WSS** to the WS server to receive events (e.g. official values of a processed activity). On reconnection, the app resynchronizes its state through the API.

The details of the layers, stores and synchronization will be specified in a dedicated ADR.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| MapKit | Limited style customization, no native heatmap, no real offline map |
| React Native / Flutter | No Android target for now, background GPS is trickier |
| Core Data / SwiftData | Less SQL control over large volumes of GPS points |
| Plain MVVM / TCA | Business logic scattered across ViewModels (MVVM); heavy dependency and boilerplate (TCA) |

## Consequences

### Positive
- Polished map rendering, routes and heatmaps without custom rendering.
- Full offline mode: data (GRDB) and base maps (Mapbox).
- Business logic testable without UI, database or network.

### Negative / Risks
- **Mapbox cost**: billing based on monthly active users beyond a free tier. Check the pricing before going to production.
- **Mapbox token** embedded in the app: minimal scopes, never committed in plain text.
- **SwiftUI integration** of Mapbox is less native than MapKit: some interactions will go through `MapView` (UIKit) via `UIViewRepresentable`.
- Mapbox/OpenStreetMap **attribution** is mandatory on the map.
- **Verbosity** of the hexagonal architecture (protocols, UseCases) and **dependency rules not enforced by the compiler** as long as everything is in a single target.
- **No type sharing with the backend** (TypeScript): the Swift network models will be generated from an OpenAPI spec (see ADR-005).

## References
- Like-Strava architecture deck, slides 01 and 02
- [ADR-001: Global architecture](ADR-001-global-architecture.md)
- Mapbox Maps SDK for iOS: https://docs.mapbox.com/ios/maps/
- GRDB.swift: https://github.com/groue/GRDB.swift

## Links

- **Depends on**: [ADR-001](ADR-001-global-architecture.md)
