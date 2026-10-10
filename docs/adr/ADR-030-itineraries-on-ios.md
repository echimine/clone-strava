# ADR-030: Itineraries on iOS (technical foundation)

- **Status**: accepted
- **Date**: 2026-10-10
- **Deciders**: echimine
- **Tags**: itineraries, mapbox, routing, elevation, ign, geo, offline, sync, realtime

## Context

Athletes want to plan an **Itinerary** (`CONTEXT.md`: a path planned by hand before going out, for one sport, private to its creator, shown as "Itinéraire") on the iOS app: a start, a finish and intermediate **Waypoints** that can be dragged, with distance and elevation gain shown while editing. The path between two consecutive Waypoints is a **Leg** ("tronçon"), which either follows roads and trails or runs in a straight line.

Scope fixed when the effort was framed: iOS only, private Itineraries, **creation online only** (routing is an online service), free for now. Out of scope: guidance during a recording, GPX export, sharing, public Itineraries, creation from an Activity, the backoffice, a premium paywall, offline tile packs.

The decisions were worked out one ticket at a time on the map [Créer et enregistrer des Itinéraires sur iOS](https://github.com/echimine/clone-strava/issues/5). The facts they depend on:

- **Mapbox Directions** ([research](https://github.com/echimine/clone-strava/issues/6)): profiles `walking` ("pedestrian and hiking … sidewalks and trails"), `cycling`, `driving`, `driving-traffic`, with no trail, MTB or gravel profile. Up to **25 coordinates** per request, billed as one. **300 requests/min per token**. Free up to 100,000 requests/month, then 2 $ per 1,000. No elevation. Product Terms §2.10.1 **forbid storing** any result of a Navigation API (geometry, distance, derived elevation), reinforced by §1.9(v) and §1.6.
- **iOS SDK**: the standalone `mapbox-directions-swift` is incompatible with our MapboxMaps 11.31.1 (Turf 2.8.x versus exactly 4.0.0). The `MapboxDirections` module of the Navigation SDK v3 pins an exact MapboxMaps version and ships native binaries.
- **Elevation** ([research](https://github.com/echimine/clone-strava/issues/14)): `MapboxMap.elevation(at:)` only covers the visible region. **IGN Géoplateforme** (RGE ALTI, 1 m bare-earth DTM) covers France and overseas departments, needs no key, is Etalab 2.0 (storage allowed), takes 5,000 points per request at 5 req/s per IP and answers in 0.6 to 0.8 s up to 1,000 points. It returns `-99999` outside its coverage. **Open-Meteo** (Copernicus GLO-90) is worldwide and fast, but it is a surface model (buildings, trees): gain measured ×2.4 in forest and ×3.3 in Paris compared to IGN. A stable gain needs resampling every ~20 m with a **2 m hysteresis**.
- **`computeMetrics`** (ADR-019 §5) skips segments with a duration `<= 0` before adding up distance and gain (`compute-metrics.ts:68`), so an untimed track gives 0. It does not smooth altitude either, contrary to what ADR-019 says.
- The iOS app has **no analytics port yet** (`Di.swift`: `TODO(ADR-015)`), and GRDB has **no table yet** (migration `v1` is empty).

## Decision

### Overview

```
iOS editor
  ├─ Mapbox Directions (REST, dedicated pk token) ── per Leg, only the Legs that changed
  ├─ POST /v1/itineraries/metrics-preview ── on release: distance + gain, nothing written
  └─ POST /v1/itineraries  |  PUT /v1/itineraries/:id ── Waypoints + Legs (polyline6)
                                │
                     apps/api · itineraries module
                       1. assemble Legs → 2D track, distance (@repo/geo)
                       2. resample every ~20 m (@repo/geo)
                       3. altitudes: elevation module (IGN, fallback Open-Meteo)
                       4. gain with hysteresis (@repo/geo)
                       5. transaction: itinerary + itinerary_waypoint + itinerary_leg
                       6. after commit: domain event → realtime bridge, PostHog event
```

### 1. Storing the computed path: deliberate deviation from Mapbox's terms

We store **the computed path, its distance and its elevation gain**, along with the Waypoints, the sport and the name, although Product Terms §2.10.1 forbid storing Directions results. Same context as the temporary geocoding endpoint of ADR-029: a non-commercial clone that will never be published.

- Without storage, every display would trigger a Directions request, the list could not show distance or gain without one request per row, and offline viewing could not draw the path.
- **Mapbox Directions stays the router**. A non-Mapbox OSM router was considered and dropped.
- **Accepted risks**: Mapbox may revoke the token if the deviation is detected. This must be fixed before any public release (store Waypoints only and recompute, or switch to a router whose data can be stored).

### 2. Routing: the app calls Mapbox Directions directly

- **No proxy in the API.** The router is a third-party service, so a proxy would add a network hop to every recomputation, noticeable while dragging a Waypoint. The question would reopen if we ever ran our own router.
- **Client**: REST with `URLSession` + `Codable` on the Directions endpoint (`geometries=polyline6`, `overview=full`, `radiuses`), with no SDK (see Context). This is the same approach as Static Images in ADR-029. §2.9.1 ("Mobile SDKs as exclusive means") remains ambiguous on this point.
- **Token**: a `pk` token **dedicated to Itineraries** in `Secrets.xcconfig`, revocable on its own and with its own 300 req/min quota. There is no per-athlete limit (impossible without a proxy). The quota is watched in the Mapbox dashboard, with a billing alert.
- **Profile**: the Itinerary has a `sport_type_code` from the existing reference data, limited to sports with GPS (`run`, `ride`, `walk`, `hike`; `swim` is rejected). The Mapbox profile is derived from the sport's `category`: `foot` → `walking`, `wheels` → `cycling`. There is no separate profile setting.
- **Leg mode**: each Leg either `follow`s roads and trails (the default) or runs `straight`. On a `follow` Leg, Mapbox snaps the Waypoint to the network (`radiuses` ≈ 200 m), and the **snapped position** is shown and stored. With no path (nothing within 200 m, or no route found), the Leg falls back to `straight`, the Waypoint stays where it was placed and a message says so. A straight line chosen by the athlete and a straight line forced by a missing path are not told apart: the enum stays `follow` / `straight`.
- **Recomputation while dragging**: while the finger moves, the neighboring Legs are drawn as dotted straight lines. A request is sent after a 300 ms pause (movement < ~8 pt) and on release, and requests that have been overtaken are cancelled. Only the Legs that changed are requested (a drag means one request with 3 points). Each Leg keeps its own geometry and a **version**. A response is applied only if the Legs it covers still have the same endpoints.
- **Pending Legs**: on a network failure, timeout, 5xx or `429`, the Leg stays `follow` but becomes **pending**. It is retried when the network returns, with exponential backoff on `429`. Only "Save" is blocked while a Leg is pending, and editing continues elsewhere.
- **Waypoint cap**: **200** Waypoints, the same limit as the API.
- **Full recomputation when the sport category changes** (foot ↔ wheels): consecutive runs of `follow` Legs are requested in batches of at most 25 points, sent **in parallel**. Neighboring batches share their junction Waypoint, which takes the position snapped by the first batch. A connector is added at the start of the next batch if it snapped the junction elsewhere (a few meters, below the API's 30 m tolerance). Every `follow` Leg becomes pending and nothing is blocked. If a batch has no path, it is requested again Leg by Leg to find the faulty Waypoint. `straight` Legs are not recomputed. A category change is one undo/redo entry.

### 3. Distance and elevation gain: the server is the source of truth

- **The app sends a 2D track; the API adds altitudes and computes.** An app that fetched altitudes itself would make the server compute on client-supplied data, and "server source of truth" would be a facade.
- **Altitudes**: IGN RGE ALTI (`ign_rge_alti_wld`, POST, no key). Points outside its coverage (`-99999`) use **Open-Meteo**. The Itinerary's **elevation source** is `ign`, `mixed` (at least one Open-Meteo point) or `open_meteo`. With `mixed` or `open_meteo`, the app shows the gain as approximate (prefixed with "≈").
- **Computation**, identical for saving and for the preview:
  1. assemble the Legs into one 2D track (a `straight` Leg is drawn by the server itself);
  2. **distance** on that exact 2D track (`trackDistanceM`);
  3. resample every **~20 m** (`resampleAlongTrack`);
  4. altitudes for the resampled points (the `elevation` module);
  5. **gain** with a **2 m** hysteresis (`elevationGainM`).

  Distance is not measured on the resampled points, which cut corners and underestimate it.
- **Preview while editing**: `POST /v1/itineraries/metrics-preview` runs exactly the save computation on the **full** track (hysteresis applies across the whole track, not Leg by Leg), so the estimate shown is the figure that will be saved. The app calls it **on release only**, giving one IGN call per gesture. The app updates the distance itself at each pause, and the gain stays greyed out until the preview answers. If the preview fails, "Elevation gain unavailable" is shown with a retry button, and nothing is blocked.
- **Saving is synchronous**: if IGN or Open-Meteo fails or answers `429`, the API returns a retryable `503`. The editor keeps everything and offers to retry. Considered and dropped: saving with a gain "being computed" and completing it in a worker job, which adds an intermediate state for a rare case.
- **What is stored**: the resampled points with their altitude (used later for the elevation profile without a new call) and the elevation source. Both licenses allow storage (Etalab 2.0, CC BY 4.0).
- **Attribution**: "Altitudes : IGN" under the stats, in the editor and in the detail, or the Open-Meteo / Copernicus variant.

### 4. Modules and packages (amends ADR-021)

- **`itineraries`**: a **domain** module, **layer 1**, with PostgreSQL schema `itineraries`. It depends on:
  - `sports`: the sport must exist and its category gives the profile; a `water` sport returns `422`;
  - `users`: only through the `user_id` foreign key, with cascade delete (GDPR);
  - `@repo/geo`.

  No dependency on `social` or `activities`. The module is added to `DOMAIN_MODULES` and `ALLOWED_DEPENDENCIES` in `.dependency-cruiser.cjs` and to the `exports` of `packages/core/package.json`.
- **`elevation`**: a **platform** module modelled on `geocoding`, registered in `apps/api` with its configuration (saving is synchronous). Its interface is `getElevations(points[]) → { altitudeM, source: 'ign' | 'open_meteo' }[]`. The Open-Meteo fallback, batching (5,000 points per IGN request, 100 per Open-Meteo request) and timeouts are internal. A provider failure surfaces as a retryable error. `itineraries` derives the global source (`ign` / `mixed` / `open_meteo`).
- **`packages/geo` (`@repo/geo`)**: pure functions, with no Nest, database or I/O, modelled on `@repo/track-files` (ADR-028):
  - `trackDistanceM(points)`: haversine sum;
  - `resampleAlongTrack(points, stepM)`: points along the track, altitude interpolated when present;
  - `elevationGainM(altitudes, hysteresisM)`: gain with a hysteresis threshold;
  - `haversineDistanceM`, `encodePolyline` and track simplification, **moved out of `activities/domain`** (`clean-trace`, `apply-privacy-zone` and the map polyline use them from here).

  Exporting these functions from `activities` was rejected (coupling with no business link), as was a shared folder in `packages/core` (not provided for by ADR-021).

### 5. Data model (amends ADR-017)

Migration **0006**, schema `itineraries`:

| Table | Columns |
|---|---|
| `itinerary` | `id` uuid **generated by the app** (no default) · `user_id` FK → `public.user.id`, cascade · `sport_type_code` FK → `sports.sport_type.code` · `name` text, 1 to 100 characters, trimmed · `distance_m` real · `elevation_gain_m` real · `elevation_source` enum `ign` / `mixed` / `open_meteo` · `track` `geometry(LineStringZ, 4326)`: points resampled every ~20 m, Z = altitude, **no GiST index** · `map_polyline` text: polyline5 of at most 2,000 characters, computed on save (ADR-029) · `created_at`, `updated_at` timestamptz |
| `itinerary_waypoint` | `itinerary_id` · `position` · `location` `geometry(Point, 4326)` (snapped position) |
| `itinerary_leg` | `itinerary_id` · `position` · `mode` enum `follow` / `straight` · `path` `geometry(LineString, 4326)`, 2D. Leg *n* joins Waypoints *n* and *n+1* |

- Index `(user_id, updated_at desc, id)` on `itinerary`.
- The two child tables are deleted in cascade and **replaced entirely** on every full update, in the same transaction. The invariant "Legs = Waypoints − 1" is checked in `domain/`.
- Storing the Legs lets the editor reopen without calling the router again.
- No elevation loss, minimum or maximum altitude: they can be derived from `track` when needed.

### 6. API: `/v1/itineraries`

Zod contracts in `packages/contracts`, then OpenAPI, then Swift (ADR-026), with response schemas documented (`@ZodResponse`, ADR-029).

| Endpoint | Behavior |
|---|---|
| `POST /v1/itineraries` | Creation, id in the body. `201` on creation, `200` when the same athlete replays it (idempotent, as in ADR-008 §4), `409` if the id belongs to another athlete |
| `PUT /v1/itineraries/:id` | Full replacement (name, sport, Waypoints, Legs), with full recomputation including altitudes. `404` if unknown |
| `PATCH /v1/itineraries/:id` | `{ name }` only (1 to 100 characters, trimmed), with no recomputation; `updated_at` changes. Used for renaming outside the editor |
| `DELETE /v1/itineraries/:id` | `204`, hard delete (ADR-017) |
| `GET /v1/itineraries/:id` | Name, sport, Waypoints, Legs (`mode` + polyline6), `distanceM`, `elevationGainM`, `elevationSource`, `createdAt`, `updatedAt`, and `track: { polyline6, altitudesM: number[] }` (as many altitudes as points) for the elevation profile |
| `GET /v1/itineraries` | Keyset cursor on `(updated_at desc, id)`, `{ items, nextCursor }`. Each item: id, name, sport, distance, gain, `mapPolyline`, `updatedAt` |
| `POST /v1/itineraries/metrics-preview` | Same `{ waypoints, legs }` body, with no name or sport. Returns `{ distanceM, elevationGainM, elevationSource }` and writes nothing. Only the global `ThrottlerModule` limit applies |

- **Request body**: `waypoints: [{ lat, lon }]`, ordered, with the snapped position for a snapped Waypoint. `legs: [{ mode: "follow", polyline6 } | { mode: "straight" }]`: a `follow` Leg carries the Mapbox geometry as is.
- **Validation**: `422` if an endpoint of a `follow` Leg is more than 30 m from its Waypoint. Safeguards: 2 to 200 Waypoints, at most 50,000 decoded points, at most 1,000 km.
- An Itinerary owned by another athlete returns `404`, not `403`.
- `503` (retryable) when an elevation provider fails during a save (§3).

### 7. Activities use the same elevation-gain algorithm (amends ADR-019 §5)

- `computeMetrics` keeps times and speeds and delegates distance and gain to `@repo/geo`. For an Activity, `resampleAlongTrack` runs on the cleaned 3D trace, then `elevationGainM`.
- Same algorithm, **parameters passed as arguments**: 20 m step and 2 m hysteresis to start with, for Activities as for Itineraries. They will be tuned on real traces, since GPS or barometer altitudes are noisier than the IGN DTM. Resampling by distance also removes the phantom gain that builds up while stopped. ADR-019's "smoothed altitude" finally becomes true.
- Distance does not change for Activities: the `<= 0` duration condition never triggers for them, because `cleanTrace` (`clean-trace.ts:47-50`) already removes those points.
- **No recomputation of Activities already processed**: only new Activities use the new algorithm (the app is not published, and an Activity can be deleted and imported again).

### 8. Mobile: offline viewing and the first sync queue (amends ADR-008)

- **Local cache (GRDB)**: **all** of the athlete's Itineraries are synced to GRDB. That covers the full list, plus each Itinerary's detail (track with altitudes, distance, gain, elevation source), prefetched whenever its `updatedAt` changes and written directly after a save. Waypoints and Legs are **not** kept: "Edit" loads them online, since the editor only works online. These are the first GRDB tables.
- **Refresh**: the full list (all pages) is re-read when the app returns to the foreground, when the Map tab sheet or Profile > My Itineraries opens, on pull-to-refresh and when the network returns (`ConnectivityMonitor`). Local rows no longer returned are deleted, unless a pending operation targets them. There is no soft delete and no `updatedSince` parameter on the API side. A `404` on a detail deletes it locally.
- **Map background**: Mapbox's automatic cache, with no guarantee (offline tile packs are out of scope). Offline, the path is drawn even when the background is missing. A missing thumbnail is replaced by the `mapPolyline` drawn locally on a neutral background.
- **`sync_operation` queue (ADR-008 §3)**: Itineraries are the **first** feature to build it, with two operations:
  - `rename_itinerary` (`PATCH`) and `delete_itinerary` (`DELETE`);
  - coalescing: only the last rename is kept, and a delete cancels a pending rename;
  - retries: exponential backoff (capped) on no network, timeout or 5xx; on `401`, refresh the session and retry;
  - `404`: a `DELETE` counts as done, a `PATCH` is dropped and the Itinerary removed locally;
  - any other 4xx on a `PATCH`: the operation is dropped, the next sync restores the server name, and a toast says the rename was refused;
  - while pending, the local value wins over the server's, and an Itinerary pending deletion stays hidden;
  - triggers: right after the action, when the network returns, when the app returns to the foreground. No `BGTaskScheduler` yet: it arrives with the upload of recorded Activities.
- **Create and edit offline**: the buttons stay active and show a "Connexion requise" toast.
- **Sign-out**: the Itinerary cache and the queue are wiped. If operations are pending, the confirmation warns that they will be lost.

### 9. Realtime events (amends ADR-010 and ADR-021 §4, §5)

After the commit, `itineraries` emits domain events. The realtime bridge forwards them on topic `user:{id}`:

| Domain event | Mobile event | Payload |
|---|---|---|
| `itineraries.itinerary.saved` (create, update, rename) | `itinerary.saved` | `{ itineraryId, updatedAt }` |
| `itineraries.itinerary.deleted` | `itinerary.deleted` | `{ itineraryId }` |

- `itinerary.saved`: the app ignores it if its local `updatedAt` is already greater than or equal (the echo of its own write); otherwise it fetches the detail and writes it to GRDB.
- `itinerary.deleted`: local delete, pending operations targeting it removed, detail closed if open.
- No catch-up: the resync on foreground and reconnection covers missed events (at-most-once delivery, ADR-010).

### 10. Analytics

- Itineraries are the first feature to emit events from the iOS app. They build the ADR-015 foundation: an `AnalyticsClient` protocol in `Core/`, an `enum AnalyticsEvent`, and a PostHog implementation wired in `Di.swift`. Session replay and automatic screen capture are disabled and app lifecycle events are enabled. The SDK is in `optOut` by default.
- The **consent screen** is out of scope (a cross-cutting topic for the whole app). Until it exists, no iOS event is sent. Backend events are sent from the start.
- The API emits the lifecycle events: `itinerary_created`, `itinerary_updated`, `itinerary_renamed`, `itinerary_deleted`, `itinerary_save_failed`. `itinerary_created` and `itinerary_updated` are emitted only when a write actually happens (a replayed `POST` emits nothing). The app emits the journey events: editor, list, detail, routing failures as session counters. The full catalog and its properties (rounded, with no coordinates) are in [Événements PostHog des Itinéraires](https://github.com/echimine/clone-strava/issues/20).

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Follow Mapbox's terms: store Waypoints only, recompute on every display | One Directions request per display, no distance or gain in the list, no offline path; disproportionate for an app that will never ship |
| Non-Mapbox OSM router (GraphHopper, Valhalla, BRouter…) whose results can be stored | Hosting or another paid API to run, for a project that accepts the deviation (§1) |
| Proxy routing through the API | Extra network hop on every recomputation while dragging; the router is not ours |
| `mapbox-directions-swift` or the Navigation SDK `MapboxDirections` module | Turf version conflict with MapboxMaps 11.31.1, or an exact MapboxMaps pin and native binaries |
| `MapboxMap.elevation(at:)` as the stored source | Visible region only, zoom-dependent precision, device only |
| The app fetches IGN altitudes and sends them | The server would compute on client-supplied data; the algorithm would be duplicated in Swift for the estimate |
| Open-Meteo everywhere | Surface model: gain ×2.4 to ×3.3 in forest and in town compared to IGN |
| Preview on the changed Legs only, gains added up | Hysteresis cut at every Waypoint: the estimate would differ from the saved figure |
| Asynchronous save, gain completed by a worker job | An intermediate "being computed" state for a rare provider failure |
| Recompute the whole Itinerary on every change | 25-point limit hit quickly, more requests, slower feedback |
| One global `follow` / `straight` mode per Itinerary | One off-road passage would force the whole Itinerary into straight lines |
| Single `measureTrack` function in `@repo/geo` | The Itinerary must call IGN between resampling and gain |
| Fixed, shared parameters, or Activities left on a raw altitude sum | Activity altitudes are noisier than a DTM; the raw sum inflates with density and while stopped |

## Consequences

### Positive

- The estimate shown in the editor is exactly the figure saved: one computation, server-side.
- Distance and gain are measured the same way for Activities and Itineraries, and ADR-019's "smoothed altitude" becomes real.
- Editing stays responsive: only changed Legs are requested, in parallel, and a network failure blocks only "Save".
- The list, the thumbnails and the detail work offline, with no Directions request per display.
- The first GRDB tables, the first `sync_operation` queue and the first iOS analytics port are built on a small, well-bounded feature.

### Negative / Risks

- **Mapbox terms**: storing Directions results breaches §2.10.1. Mapbox may revoke the dedicated token, and the editor would then stop routing (saved Itineraries stay readable). Must be fixed before any public release.
- **Unlimited client quota**: with no proxy, one athlete can consume the shared 100,000 free requests/month. Watched in the Mapbox dashboard only.
- **IGN dependency for saving**: an IGN outage blocks saves in France (retryable `503`). Rate limit of 5 req/s per IP shared by the whole API.
- **Approximate gain outside France**: Open-Meteo overestimates it. Shown with "≈", not corrected.
- **Activity parameters not calibrated**: 20 m / 2 m come from a DTM. Activity gain may change compared to before this ADR, and older Activities keep the old figure.
- **Lost straight-line intent**: after a foot → wheels → foot round trip, a Leg that fell back to `straight` stays straight, and the athlete switches it back by hand.
- **No iOS events until a consent screen exists.**

## References

- Research: [Mapbox routing and elevation](https://github.com/echimine/clone-strava/blob/research/mapbox-itinerary-routing/docs/research/mapbox-itinerary-routing.md), [Itinerary elevation source](https://github.com/echimine/clone-strava/blob/research/itinerary-elevation-source/docs/research/itinerary-elevation-source.md)
- Map and decision tickets: [Créer et enregistrer des Itinéraires sur iOS](https://github.com/echimine/clone-strava/issues/5)
- Mapbox Directions API: https://docs.mapbox.com/api/navigation/directions/
- Mapbox Product Terms: https://www.mapbox.com/legal/product-terms
- IGN Géoplateforme altimetry: https://geoservices.ign.fr/documentation/services/services-geoplateforme/altimetrie
- Open-Meteo Elevation API: https://open-meteo.com/en/docs/elevation-api

## Links

- **Amends**: [ADR-005](ADR-005-monorepo.md) (adds `packages/geo`), [ADR-008](ADR-008-mobile-offline-sync.md) (§3 first `sync_operation` operations, Itinerary cache), [ADR-010](ADR-010-backend-realtime.md) (`itinerary.saved`, `itinerary.deleted`), [ADR-017](ADR-017-data-model.md) (`itineraries` schema and tables), [ADR-019](ADR-019-activity-creation-flow.md) (§5 elevation-gain algorithm), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (`itineraries` domain module, `elevation` platform module, `@repo/geo`, bridge table)
- **Related**: [ADR-002](ADR-002-mobile.md), [ADR-006](ADR-006-mobile-stack.md), [ADR-007](ADR-007-mobile-architecture.md), [ADR-015](ADR-015-posthog.md), [ADR-026](ADR-026-openapi-swift-codegen.md), [ADR-027](ADR-027-user-location-on-maps.md), [ADR-028](ADR-028-activity-import-from-file.md) (`@repo/track-files` model for `@repo/geo`), [ADR-029](ADR-029-activity-feed-and-card.md) (same kind of Mapbox deviation, `map_polyline`)
