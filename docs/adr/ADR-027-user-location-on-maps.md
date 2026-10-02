# ADR-027: User location on maps: one GPS source feeding the Mapbox puck, shared `AppMap` component

- **Status**: accepted
- **Date**: 2026-10-02
- **Deciders**: echimine
- **Tags**: mobile, mapbox, core-location, gps, swiftui, architecture

## Context

The Map tab (`Features/Map/Presentation/MapScreen.swift`) shows a Mapbox Outdoors map centered on Paris. It does not show the user's position yet. Three screens will need a map with the user's location, as in Strava:

- **Map tab**: explore around you;
- **Route creation** (later): place points and get a route from the Directions API;
- **Recording**: live trace and position while recording an activity.

Two needs that look alike have to be kept apart:

- **Display**: the blue dot ("puck"), its heading, and a camera that follows it. This is UI only.
- **Tracking**: the stream of GPS fixes that becomes an activity, with accuracy filtering, distance and pace, background updates and crash recovery. This is domain data. It already exists in `Features/Recording` (ADR-006, ADR-007): a `LocationProvider` protocol in `Recording/Domain`, a `CoreLocationProvider` (`CLLocationUpdate.liveUpdates(.fitness)` + `CLBackgroundActivitySession`) in `Recording/Infrastructure`, and `RecordingService`, which consumes it.

By default, Mapbox's puck uses its own `AppleLocationProvider`, which is a second `CLLocationManager`. During a recording, the dot and the trace would then come from two different streams, which can drift apart in time, accuracy and filtering. Three other problems follow:

- ADR-007 rule 5 ("a feature does not import another feature") prevents the Map feature from reusing the Recording `LocationProvider`.
- The current provider is single-consumer: `start()` cancels any previous stream.
- It also requests authorization on its own, which is wrong once several screens depend on location.

We also discussed whether a classic GoF **Builder** (`MapBuilder().withPuck().withStyle(...).build()`) should configure these maps.

## Decision

### 1. Display and tracking are separate concerns

- **Display** lives in presentation code: map style, puck, viewport, the recenter button. Viewport and follow state are ephemeral UI state, held in `@State` in the view, with no store.
- **Tracking** stays in the domain and application layers. `RecordingService` consumes location samples, and `RecordingStore` exposes the trace. The map only renders what it is given.

### 2. Single source of truth: one shared location provider in `Core`

Location becomes a shared building block, like `ConnectivityMonitor`:

| Element | Location | Notes |
|---|---|---|
| `LocationSample` | `Core/Domain/` (moved from `Recording/Domain`) | Gains `course: Double?` |
| `LocationProvider` protocol | `Core/Domain/` (moved from `Recording/Domain`) | Multi-subscriber (see below) |
| `CoreLocationProvider` | `Core/Location/` (moved from `Recording/Infrastructure`) | The **only** GPS updates loop (`liveUpdates`) and heading source in the app |
| `LocationPermissionService` | `Core/Location/` | See §5 |

The protocol becomes **multi-subscriber**, with reference-counted updates:

```swift
protocol LocationProvider: Sendable {
    func samples() async -> AsyncStream<LocationSample>   // one stream per subscriber
    func headings() async -> AsyncStream<Double>          // degrees, for the puck bearing
    func beginBackgroundTracking() async                  // Recording only: CLBackgroundActivitySession
    func endBackgroundTracking() async
}
```

- The `liveUpdates` loop runs while at least one subscriber exists and stops when the last stream terminates, which saves battery.
- Each sample is broadcast to every subscriber.
- The live configuration is `.fitness` in every case. Background updates are opt-in through `beginBackgroundTracking()`, which only Recording calls.
- `RecordingService` subscribes to `samples()` and brackets a recording with `begin/endBackgroundTracking()`, in place of `start()`/`stop()`.
- `App/Di.swift` creates **one** `CoreLocationProvider` and injects it into the Recording service and the map layer.

### 3. The Mapbox puck is fed from our stream

`Core/DesignSystem/Map/MapboxLocationBridge.swift` adapts our provider to Mapbox:

- It holds Combine subjects of Mapbox `Location` and `Heading`. It converts `LocationSample`, including `course` as the bearing, and our heading stream.
- It exposes them as a `LocationDataModel(location:heading:)`, installed with the SwiftUI `Map` modifier `.locationDataModel(_:)`. The older `location.override(provider:)` is deprecated as of Maps SDK 11.31.
- `run(provider:)` subscribes to `samples()` and `headings()` for the lifetime of the map's `.task`. When the map leaves the screen, the streams terminate and the GPS stops unless Recording still listens.

Mapbox's `AppleLocationProvider` is therefore never created, and the app runs a single GPS updates loop. The bridge does not conform to Mapbox's `LocationProvider` protocol, so there is no name clash with ours.

### 4. A thin shared `AppMap` component, no GoF Builder

`Core/DesignSystem/Map/AppMap.swift` is a SwiftUI view used by every map screen:

```swift
AppMap(viewport: $viewport, showsUserLocation: true) {
    Polyline(trace)   // screen-specific content through @MapContentBuilder
}
```

- It centralizes what is common: the Outdoors style, `Puck2D(bearing: .heading)` with the accuracy ring, the bridge from §3, the recenter button (`withViewportAnimation { viewport = .followPuck(zoom:) }`), ornaments and the accessibility identifier.
- Each screen adds its own content through a `@MapContentBuilder` closure: the live trace for Recording, the route and points for route creation.
- A GoF Builder object is **rejected**. SwiftUI already provides composable configuration through modifiers and result builders, and Mapbox's `@MapContentBuilder` is one. A builder object would not fit `Binding<Viewport>` or the view lifecycle, and it would add a second API on top of Mapbox's.
- The component grows only when a real screen needs it, with no speculative options.

### 5. Location permission is app-wide

`LocationPermissionService` (`@Observable`, `@MainActor`, `Core/Location/`) is injected through the SwiftUI `environment` from `Di`, like `ConnectivityMonitor`:

- It exposes `authorizationStatus` and observes it through `CLLocationManager`'s delegate.
- It provides `requestWhenInUse()` and `openSettings()`.
- It is the **only** place that requests authorization. `CoreLocationProvider` no longer does.
- It owns its own `CLLocationManager`, used **only** for authorization status and requests. It never starts updates, so the single-GPS-source rule still holds.
- `Info.plist` gets `NSLocationWhenInUseUsageDescription`. `NSLocationAlwaysAndWhenInUseUsageDescription` is deferred until Recording needs it (ADR-006 §Core Location).

### 6. Map tab behavior

- The initial viewport is `.followPuck(zoom: 15)`, so the map follows the user.
- When the user pans, Mapbox moves the viewport to idle and the recenter button appears. Tapping it returns to `.followPuck`.
- If permission is denied or restricted, the map falls back to the current Paris camera and shows a banner that opens Settings.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Mapbox `AppleLocationProvider` for the puck, our provider for recording | Simplest, but two `CLLocationManager`s: the dot and the trace can disagree, battery use is doubled, and the permission request comes from two places |
| Keep `LocationProvider` in `Features/Recording` and import it from Map | Breaks ADR-007 rule 5; route creation would need it too |
| GoF Builder object for maps | Not idiomatic in SwiftUI, does not fit bindings, duplicates `@MapContentBuilder` (§4) |
| A `MapStore` per map screen | The map state (viewport, follow mode) is ephemeral UI state; a store adds wiring with no benefit |
| Each map screen configures Mapbox itself | Puck, bridge and recenter logic duplicated three times |

## Consequences

### Positive
- One GPS stream: the puck is exactly the position Recording stores, and there is one battery cost and one permission path.
- Map, route creation and Recording share one component and differ only in their content.
- The location provider is testable at the `Core/Domain` boundary. ADR-025's `FakeLocationProvider` moves to `TestSupport` and can drive both the map (previews, UI tests) and Recording.

### Negative / Risks
- **More code than the default puck**: the bridge, the multi-subscriber broadcast (`LocationBroadcaster`) and the permission service.
- **Refactor of existing Recording code**: `LocationSample`, `LocationProvider` and `CoreLocationProvider` move to `Core`, and `RecordingService` and its tests switch to `samples()`/`begin/endBackgroundTracking()`.
- **Swift 6 isolation**: `LocationDataModel` requires main-thread delivery, so the bridge is `@MainActor`.
- **Heading** uses `CLLocationManager.startUpdatingHeading`, which is not part of `liveUpdates`. The same manager handles it, so the single source still holds.

## References
- [Mapbox iOS: User location](https://docs.mapbox.com/ios/maps/guides/user-location/)
- [Mapbox iOS v11 migration: Location API, custom `LocationProvider`](https://github.com/mapbox/mapbox-maps-ios/blob/main/Sources/MapboxMaps/Documentation.docc/Articles/Migrate%20to%20v11.md)
- [Mapbox SwiftUI user guide: `Puck2D`, `.followPuck`, `MapReader`](https://github.com/mapbox/mapbox-maps-ios/blob/main/Sources/MapboxMaps/Documentation.docc/Articles/SwiftUI%20User%20Guide.md)
- [`CLLocationUpdate.liveUpdates`](https://developer.apple.com/documentation/corelocation/cllocationupdate)

## Links
- **Depends on**: [ADR-006](ADR-006-mobile-stack.md), [ADR-007](ADR-007-mobile-architecture.md)
- **Amends**: [ADR-007](ADR-007-mobile-architecture.md) (GPS moves from `Features/Recording` to `Core/Location`; rule 6 allows Mapbox in `Core/DesignSystem/Map/`), [ADR-025](ADR-025-mobile-testing-strategy.md) (`FakeLocationProvider` is a `Core` fake)
- **Related**: [ADR-002](ADR-002-mobile.md), [ADR-019](ADR-019-activity-creation-flow.md)
