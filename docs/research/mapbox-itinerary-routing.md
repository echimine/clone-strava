# Research: Mapbox routing and elevation for Itineraries

- **Ticket**: [#6 Routage et dénivelé Mapbox pour les Itinéraires](https://github.com/echimine/clone-strava/issues/6) (wayfinder map [#5](https://github.com/echimine/clone-strava/issues/5))
- **Date**: 2026-10-09
- **Scope**: what Mapbox allows and forbids when an athlete builds an **Itinerary** on iOS (start, finish, draggable intermediate **Waypoints**, path following roads/trails, live distance and elevation gain, private save, online-only creation).
- **Sources**: Mapbox docs, the Mapbox Product Terms PDF (last updated July 21, 2026), the Mapbox pricing page, and the `mapbox/*` GitHub repos, all read on 2026-10-09. Quotes are verbatim. Where a source is silent or contradicts another source, this file says so.

> Vocabulary: "Itinerary" and "Waypoint" are the domain terms. Mapbox's own API uses `route`/`routes` and `waypoints`. Those words appear here only as literal API field names in code formatting.

---

## TL;DR

1. **Directions API** has 4 profiles: `driving-traffic`, `driving`, `walking`, `cycling`. There is **no dedicated trail, hiking or MTB profile**. `walking` is described as "for pedestrian and hiking routing … using sidewalks and trails". Every profile accepts **up to 25 coordinates** per request, billed as **1 request**. Geometry comes as `polyline` (default, precision 5), `polyline6` or `geojson`, with `overview=full|simplified|false`. The limit is **300 requests/min per access token**, and each request is capped at 1,500 km for `cycling` and 1,000 km for `walking`.
2. **Storage: no.** Product Terms §2.10.1: *"Customer shall not export, download, cache or store results from any request to a Navigation API."* Directions and Map Matching are Navigation APIs. §1.9(v) and §1.6 also forbid storing results or deriving data from them. Taken literally, we may store only what the athlete supplied (the Waypoint coordinates they placed) and must re-request the path whenever an Itinerary is displayed. Persisting the geometry, distance or a derived elevation gain would breach the terms. The project already accepted a similar deviation for geocoding in ADR-029.
3. **Elevation**: Directions returns none. The practical Mapbox option is **on device**. With 3D terrain enabled (Mapbox Terrain-DEM v1, "only available for use in the Mapbox SDKs"), `MapboxMap.elevation(at:)` returns metres for coordinates in the **visible region**. The data has 0.1 m increments and zoom 14 tiles. The **Tilequery API** on `mapbox-terrain-v2` contours has only **10 m increments** and needs one request per point, so it does not fit elevation-gain computation. Server-side **Terrain-RGB v1** via the Raster Tiles API still works, but that tileset has been frozen since Dec 1, 2021, and the same no-store/no-derive terms apply.
4. **Pricing**: Directions is **free up to 100,000 requests/month**, then $2.00 / $1.60 / $1.20 per 1,000 by tier. Tilequery is free up to 100,000, then from $1.50 per 1,000. Raster Tiles are free up to 750,000, then from $0.25 per 1,000. The Maps SDK for iOS is free up to 25,000 MAU. If each Waypoint drag triggers one Directions request, the free tier covers roughly 100k drags per month across all users.
5. **iOS SDK**: the standalone `mapbox-directions-swift` (v2.15.0, Aug 2026) is still maintained. It **cannot be added next to our MapboxMaps 11.31.1**, because it pins `turf-swift` 2.8.x while MapboxMaps pins Turf **exactly 4.0.0**. Its API is completion-handler based and not `Sendable`-annotated. The Navigation SDK v3 ships a Swift-6-friendly `MapboxDirections` module, but it pins an exact MapboxMaps version and pulls in the navigation native binaries. **Plain REST through `URLSession`** with `Codable` and `Sendable` structs is the simplest Swift 6 option. Product Terms §2.9.1 (Mobile SDKs as "exclusive means" of access in mobile apps) is ambiguous on this point; see §5.
6. **Tokens**: Directions and Tilequery only need "a valid Mapbox access token", with no specific scope, so the app's existing public `pk` token works. URL restrictions **do not apply** to native mobile requests. Rate limits are counted **per token**, so a dedicated Directions token isolates the 300/min budget. A server token (a public-scope `pk`, like `MAPBOX_GEOCODING_TOKEN`) is needed only if the backend itself calls Mapbox.

---

## 1. Directions API

Source: <https://docs.mapbox.com/api/navigation/directions/>

### Profiles

| Profile | Mapbox description (verbatim) |
|---|---|
| `mapbox/driving-traffic` | "For automotive routing. This profile factors in current and historic traffic conditions to avoid slowdowns." |
| `mapbox/driving` | "For automotive routing. This profile shows the fastest routes by preferring high-speed roads like highways." |
| `mapbox/walking` | "For pedestrian and hiking routing. This profile shows the optimal path by using sidewalks and trails." |
| `mapbox/cycling` | "For bicycle routing. This profile shows routes that are short and safer for cyclists by avoiding highways and preferring streets with bike lanes." |

- **No trail/hiking/MTB/road-bike profile exists.** For trail running and hiking, `walking` is the closest. For cycling there is a single profile that prefers bike lanes. There is no road-vs-gravel-vs-MTB distinction.
- Profile-specific tuning is small. `walking` has `walking_speed` and `walkway_bias` ("A scale from -1 to 1, where -1 biases the route against walkways and 1 biases the route toward walkways"). `exclude=unpaved` exists only for `driving`/`driving-traffic`. For `walking`/`cycling`, only `ferry` and `cash_only_tolls` can be excluded.
- `continue_straight` "Defaults to … false for mapbox/walking and mapbox/cycling", so the path may turn back at an intermediate Waypoint, which matches an out-and-back Itinerary.

### Waypoints per request

- "`coordinates` … A semicolon-separated list of between two and 25 {longitude},{latitude} coordinate pairs to visit in order."
- "Requests using the `driving`, `driving-traffic`, `walking`, and `cycling` profiles can specify up to 25 total waypoints". With `engine=electric` the limit is 12, which is irrelevant here.
- "A request that contains multiple waypoints is billed as a single API request."
- "Maximum total distance between all waypoints: 10,000 kilometers for the driving and driving-traffic profiles. 1,500 kilometers for the cycling profile. 1,000 kilometers for the walking profile."
- "The Directions API has a size limit of approximately 8100 bytes on `GET` request URLs." HTTP `POST` is supported for larger requests.
- Implication: an Itinerary is capped at **start + 23 intermediate Waypoints + finish = 25**, unless the client splits it into several requests, each billed separately.

### Geometry and overview

- `geometries`: `polyline` (default, "a polyline with a precision of five decimal places"), `polyline6` ("a polyline with a precision of six decimal places"), `geojson` ("as LineString").
- `overview`: `full` ("the most detailed geometry available"), `simplified` (default, "a simplified version of the full geometry"), `false` ("no overview geometry").
- `annotations` (`distance`, `duration`, `speed`, …) "Must be used in conjunction with `overview=full`."
- For editing, request `overview=full&geometries=polyline6`. Polyline5 is what ADR-029 already uses for `map_polyline`. The response gives `routes[0].distance` in metres and per-leg distances (one leg per pair of consecutive Waypoints).
- **No elevation** in the response: there is no elevation field or annotation.

### Rate limits

- "Maximum 300 requests per minute." ([Directions restrictions and limits](https://docs.mapbox.com/api/navigation/directions/))
- "Note that all rate limits are counted per access token, not per account." ([API guides, rate limits](https://docs.mapbox.com/api/guides/))
- Map Matching: "The Map Matching API is limited to 300 requests per minute. Each regular request can have a maximum of 100 coordinates." ([Map Matching](https://docs.mapbox.com/api/navigation/map-matching/))
- With one shared app token, 300 drags per minute across **all** athletes is the ceiling, so drags should be debounced (request on drag end, not on every frame).

---

## 2. Terms: may we store the computed path, distance and elevation?

Source: **Mapbox Product Terms, last updated July 21, 2026** ([page](https://www.mapbox.com/legal/product-terms), [PDF](https://cdn.prod.website-files.com/609ed46055e27a02ffc0749b/6a60463142f6478d57642594_Mapbox%20Product%20Terms%20(July%2021%2C%202026).pdf)).

### The clauses

> **2.10 Navigation APIs/SDK.** […] **2.10.1. Navigation APIs.** Customer shall not export, download, cache or store results from any request to a Navigation API.

> **3.51** "Navigation APIs" means Mapbox's navigation service APIs as described in Mapbox documentation. Navigation APIs may be accessed directly or through a Navigation SDK.

The Mapbox docs list **Directions, Map Matching and Isochrone** under the Navigation service ([docs.mapbox.com/api/navigation](https://docs.mapbox.com/api/navigation/)). Directions **and** Map Matching are therefore covered by §2.10.1.

> **1.9 Default Restrictions.** Except as otherwise expressly permitted under these Product Terms, Customer shall (i) only query the Services in response to human user queries and human application interactions, (ii) not perform bulk or automated queries, (iii) not scrape or systematically download Licensed Map Content, (iv) only access Licensed Map Content (other than Data Products) directly from Mapbox APIs, and (v) not export, download, cache or store Licensed Map Content or other results from the Service Offerings.

> **1.6 No Tracing, Deriving, or Extracting.** Customer shall not trace or otherwise derive or extract content, data and/or information from the Service Offerings except that Customer may use Studio or third-party software to trace Mapbox Maps solely comprised of satellite imagery to produce derivative vector datasets (i) for non-commercial purposes or (ii) for OpenStreetMap.

> **1.10 No Redistribution.** Except as otherwise expressly permitted under the Agreement, Customer shall not redistribute, encumber, sell, rent, lease, sublicense, assign, disclose, distribute, or otherwise transfer any rights to (or any content, data and/or information from) the Service Offerings.

> **2.8.1** For Licensed Map Content delivered through a Mapping API, Customer may cache that Licensed Map Content on an End User's device but caching is limited to thirty (30) days on the same device making the Mapping API request. […] Customer shall not distribute Licensed Map Content, including from a cache, by proxying, or by using a screenshot or other static image instead of accessing Licensed Map Content directly from the Mapping APIs.

> **1.19 Data.** Notwithstanding anything herein to the contrary, nothing in this Agreement shall restrict or limit (i) use by Customer of any data that Customer has the right to access and use independent of the Agreement […]

Display requirement:
- **Map Matching** docs: "Results must be displayed on a Mapbox map using one of the Mapbox libraries or SDKs." ([Map Matching restrictions](https://docs.mapbox.com/api/navigation/map-matching/))
- The current **Directions** docs page has **no** equivalent sentence. Directions results are still "results from the Service Offerings" under §1.9(v).
- **Attribution** (§1.4.1) is mandatory whenever a Service Offering is used: the Mapbox logo, plus "© Mapbox" and "© OpenStreetMap" when Licensed Map Content is used. The Maps SDK map view already renders these.

Unlike geocoding, there is **no "permanent" tier** for Directions. Geocoding has `permanent=true` (§2.7.3, "Customer may permanently store Permanent Geocodes"), but nothing in the Product Terms grants storage rights for Navigation API results.

### What this means for an Itinerary

| Data | Origin | Storable under the terms? |
|---|---|---|
| Waypoint coordinates **as placed by the athlete** (taps, drags, start, finish) | Athlete input | **Yes**: our own data (§1.19). Store the raw input, not the snapped `waypoints[].location` that Directions returns. |
| Profile (`walking`/`cycling`) and Itinerary name | Athlete input | Yes |
| Path geometry (polyline) | Directions result | **No** (§2.10.1, §1.9(v)) |
| Distance (`routes[0].distance`, or our own sum over the geometry) | Directions result, or derived from it | **No** (§2.10.1, §1.6) |
| Elevation gain computed from Mapbox terrain | Derived from Mapbox tiles | **No** (§1.6, §1.9(v)) |
| Thumbnail from a stored polyline (like ADR-029 `map_polyline`) | Needs the stored geometry | No as above. Building the Static Images URL at display time from a freshly requested path is fine. |

Strictly compliant shape: persist Waypoints and profile only. Every time an Itinerary is shown (list thumbnail, detail, edit), the client re-requests Directions and recomputes elevation on device. Consequences:
- Each display costs one Directions request, plus one Static Image for a thumbnail.
- The list cannot show distance or elevation gain without one request per row.
- **Offline viewing** (map #5 "Not yet specified", ADR-008) cannot show the path, except from the on-device cache, which §2.8.1 limits to 30 days for Mapping APIs. Directions is a Navigation API, and §2.10.1 forbids caching its results at all.
- Mapbox may change the computed path between two views (data updates), so the Itinerary is not stable over time.

Alternatives, for the driving session to decide:
- **(a) Comply**: store Waypoints only, as above.
- **(b) Deliberate deviation**: store the geometry, distance and elevation gain anyway, as ADR-029 did for temporary geocodes ("a deliberate deviation from Mapbox's terms" in a non-commercial, unpublished clone). The same risk applies: token revocation, and a fix required before any public release.
- **(c) Non-Mapbox router**: a self-hosted or OSM-based engine whose output we may store, such as GraphHopper, Valhalla or BRouter, all on OSM data under ODbL. Not researched in depth here.

---

## 3. Elevation

The Directions API returns no elevation, so every option below is a separate data source.

### 3a. On device: Maps SDK `elevation(at:)` with 3D terrain (Terrain-DEM v1)

- Tileset: **Mapbox Terrain-DEM v1** ([reference](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-dem-v1/)):
  - "Mapbox Terrain-DEM-v1 is only available for use in the Mapbox SDKs, including Mapbox GL JS, Maps SDK for iOS, Maps SDK for Android, Maps SDK for Flutter. It is not available via the Raster Tiles API."
  - "Data is available up to zoom 14. Renderers will interpolate and smooth at higher zoom levels but will not increase the resolution of the data loaded by your application."
  - "Elevation data is mapped to 0.1 meter height increments."
  - "Mapbox Terrain-DEM uses multiple data sources depending on the zoom level and location. Different sources often use different vertical datum references […] attempting to normalize Mapbox elevation data to a particular geoid or vertical datum may lead to inaccuracies in data."
- iOS API ([`MapboxMap.swift`, mapbox-maps-ios](https://github.com/mapbox/mapbox-maps-ios/blob/main/Sources/MapboxMaps/Foundation/MapboxMap.swift)):
  ```swift
  /// Gets elevation for the given coordinate.
  /// - Note: Elevation is only available for the visible region on the screen.
  /// - Returns: Elevation (in meters) multiplied by current terrain
  ///     exaggeration, or empty if elevation for the coordinate is not available.
  public func elevation(at coordinate: CLLocationCoordinate2D) -> Double?
  ```
  `MapboxMap` is a main-thread type, so call it from `@MainActor` code.
- Practical constraints:
  - Terrain must be enabled on the style (a `raster-dem` source with `mapbox.mapbox-terrain-dem-v1`, plus `Terrain`), with **exaggeration 1**. Otherwise the values are multiplied.
  - Only coordinates **on screen** return a value. When the Itinerary extends beyond the viewport, segments off screen yield `nil`, and the camera would have to fit the whole Itinerary.
  - The values come from tiles loaded for the current zoom. Because of the "compression to reduce precision at lower zoom levels", a zoomed-out view of a long Itinerary gets coarser elevation than zoom 14.
  - Precision: the DEM's maximum pixel spacing at zoom 14 with 512 px tiles is about 4.8 m at the equator (about 3.4 m at 45° N). This figure is computed, not documented. True accuracy depends on the unnamed source data, which Mapbox does not document.
  - Sampling along the geometry and applying a noise threshold before summing positive deltas is our own job.
- Cost: no per-request charge. The tiles come with the Maps SDK, which is billed per MAU, and the [Maps SDK pricing guide](https://docs.mapbox.com/ios/maps/guides/pricing/) says "Maps SDK MAUs cover any use of the Vector Tiles API and Raster Tiles API". The guide **does not name DEM tiles explicitly**, so this is likely but unconfirmed.
- Storage: the value is derived from Licensed Map Content, so §1.6 and §1.9(v) apply. Displaying it live while editing is fine. Persisting it is not (see §2).

### 3b. Tilequery API on `mapbox-terrain-v2` contours

- [Access elevation data guide](https://docs.mapbox.com/data/tilesets/guides/access-elevation-data/): "Mapbox Terrain includes features in the contour source layer that contain a property called `ele` […] Data is mapped to **10 meter height increments**." "The Mapbox Tilequery API allows you to query features at a **single point**. To find elevation along a line, you will have to turn your line into a series of points."
- [Mapbox Terrain v2](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-v2/): the contour interval is 10 m from zoom 14 up, and coarser at lower zooms.
- [Tilequery API](https://docs.mapbox.com/api/maps/tilequery/): "The default rate limit for the Mapbox Tilequery API endpoint is 600 requests per minute." Each point is one billed request. "The Tilequery API does not support raster tilesets."
  - The Terrain-RGB v1 page still shows a Tilequery URL template for `mapbox.terrain-rgb`, which contradicts that sentence. I have not tested it.
- Verdict: elevation gain from 10 m contour steps is far too coarse, and N requests per drag is expensive and quickly rate-limited. **Not suitable.**

### 3c. Server side: Terrain-RGB v1 via the Raster Tiles API

- [Terrain-RGB v1](https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-rgb-v1/): tiles are available through `https://api.mapbox.com/v4/mapbox.terrain-rgb/{z}/{x}/{y}.pngraw`, decoded with `height = -10000 + ((R * 256 * 256 + G * 256 + B) * 0.1)`. "The data is encoded to the equivalent of zoom 15 at 256 tile resolution (and zoom 14 for 512 tiles)."
- However: "**As of December 1, 2021, elevation data updates will not be applied to the Mapbox Terrain-RGB tileset.** Data updates will be applied to the Mapbox Terrain-DEM tileset".
- Terms: a backend fetching tiles is not an "End User's device", so §2.8.1's 30-day caching allowance does not apply. §1.9(v) forbids caching or storing, and §2.8.1 forbids "proxying". The backend could decode tiles on the fly for one computation, but could not keep the tiles or persist the result.
- Cost: see Raster Tiles in §4. A long Itinerary at zoom 14 spans a few tiles to a few dozen tiles.

### 3d. Non-Mapbox alternatives (brief, not researched in depth)

- **IGN Géoplateforme "Calcul altimétrique"** (France only, RGE ALTI / BD ALTI): elevation of points and profiles along a line, limited to 5 requests per second per IP ([data.gouv.fr listing](https://www.data.gouv.fr/dataservices/api-geoplateforme-calcul-altimetrique)). It is French open data, so storing results should be allowed. Check the licence before relying on it.
- **Valhalla `/height`** (self-hosted): elevation for a `shape` or `encoded_polyline`, with optional `range` and `resample_distance`, from the AWS Public Datasets terrain tiles ([Valhalla elevation API](https://valhalla.github.io/valhalla/api/elevation/)). The same engine could also replace Directions (option 2c).
- Activities already compute elevation from the athlete's own GPS file (ADR-028), so those figures are unaffected by any of this.

---

## 4. Pricing

Source: <https://www.mapbox.com/pricing>, read on 2026-10-09. Prices are per 1,000 units per month.

| Service | Free | Paid tiers |
|---|---|---|
| Directions API (requests) | 0–100,000 | $2.00 (100,001–500k), $1.60 (500,001–1M), $1.20 (1,000,001–5M), contact sales above 5M |
| Map Matching API (requests) | 0–100,000 | same as Directions |
| Tilequery API (requests) | 0–100,000 | $1.50, $1.20, $0.90, contact sales above 5M |
| Raster Tiles API (tiles) | 0–750,000 | $0.25 (to 2M), $0.20 (to 4M), $0.15 (to 20M) |
| Vector Tiles API (tiles) | 0–200,000 | $0.25, $0.20, $0.15 |
| Static Images API (requests) | 0–50,000 | $1.00, $0.80, $0.60 |
| Maps SDK for iOS (MAU) | 0–25,000 | $4.00, $3.20, $2.40 |

- Walking and cycling cost the same as driving. A multi-Waypoint request counts as 1 request.
- **Scenario (each Waypoint drag = 1 Directions request, elevation computed on device with 3a):**
  - The marginal cost per drag is 1 Directions request, because DEM tiles fall under the MAU, likely but unconfirmed (§3a).
  - **100,000 drags/month free.** Example: 1M drags/month = 400k × $2.00 + 500k × $1.60 per 1,000 = **≈ $1,600/month**.
  - In the compliant "store Waypoints only" shape (§2), every **display** of an Itinerary also costs one Directions request, and a list thumbnail one Static Image.
- **With Tilequery for elevation**, a drag would cost 1 Directions request plus N Tilequery requests (N = sample points, say 50–200), which exhausts the 100k free requests after about 500–2,000 drags. That is not viable.
- **With Terrain-RGB server side**, each computation costs a few to a few dozen tiles against 750k free per month. That is cheap, but the data has been frozen since 2021 and the terms limit what the backend may do (§3c).

---

## 5. iOS: `mapbox-directions-swift` SDK vs REST

App context: `apps/mobile/project.yml` sets `SWIFT_VERSION: "6.0"` and `SWIFT_STRICT_CONCURRENCY: complete`. The app resolves `mapbox-maps-ios` **11.31.1** with `turf-swift` **4.0.0** (`Package.resolved`).

### Standalone `mapbox/mapbox-directions-swift`

Repo: <https://github.com/mapbox/mapbox-directions-swift>

- Status: not archived. Latest release **v2.15.0, 2026-08-25** (previous v2.14.4 on 2026-06-18). Last push 2026-09-15. 32 open issues. ISC licence. The README says CocoaPods distribution ends in **December 2026** and recommends SPM.
- `Package.swift`: `swift-tools-version:5.5` and **`.package(name: "Turf", url: "https://github.com/mapbox/turf-swift.git", "2.8.0"..<"2.9.0")`**.
- `mapbox-maps-ios` `Package.swift` (main): `let turfVersion: Version = "4.0.0"` … `.package(url: "https://github.com/mapbox/turf-swift.git", exact: turfVersion)`.
- **The two requirements cannot be satisfied together**, so SPM cannot resolve this package alongside our Maps SDK. This conclusion comes from reading both manifests; I did not run an actual resolve.
- The API is a completion handler on an `NSObject` subclass: `open func calculate(_ options: RouteOptions, completionHandler: @escaping RouteCompletionHandler) -> URLSessionDataTask`, with "This closure is executed on the application's main thread". A code search finds only one `Sendable` conformance in the package (an internal log category). Under Swift 6 strict concurrency, expect `Sendable` warnings or errors when results cross isolation domains.

### `MapboxDirections` module inside the Navigation SDK v3 (`mapbox/mapbox-navigation-ios`)

Repo: <https://github.com/mapbox/mapbox-navigation-ios>

- The package exposes a `.library(name: "MapboxDirections", …)` product built on Turf `exact: "4.0.0"`.
- Its `Directions` class is `open class Directions: @unchecked Sendable` with `@Sendable` completion handlers, so it is Swift-6 friendly.
- Releases are active (3.30.5 on 2026-10-09).
- But the package manifest pins **`mapsVersion: Version = "11.30.5"`** (at tag 3.30.5) and `mapbox-navigation-native-ios` / `mapbox-navigation-cpp-ios` exact versions. SPM resolves all of a package's dependencies even when only one product is used. Using it would lock MapboxMaps to the Nav SDK's exact version (currently one minor version behind ours) and add binary dependencies, all just to get a REST client.

### Plain REST via `URLSession`

- One `GET https://api.mapbox.com/directions/v5/mapbox/{walking|cycling}/{lon,lat;…}?geometries=polyline6&overview=full&access_token=…`, or `POST` for long coordinate lists.
- Decode with `Codable` structs. Value types are implicitly `Sendable`, and `async` `URLSession` fits strict concurrency without friction.
- We decode polyline6 ourselves, a short function (the server already handles polyline5 in ADR-029). We also own the error mapping: `NoRoute`, `NoSegment`, and HTTP 429 for rate limiting. The app already calls the Static Images API by URL (ADR-029), so this would not be a new pattern.
- **Terms caveat**: §2.9.1 says *"Customer shall use the Mobile SDKs as Customer's exclusive means of accessing the Service Offerings in mobile applications."* "Mobile SDKs" is defined (§3.49) as "the Mapbox SDKs for mobile applications, including the Maps SDK and Navigation SDK for Mobile". Read strictly, it pushes toward an official SDK, either the Nav SDK `MapboxDirections` module or the standalone client, rather than hand-written HTTP. The clause is ambiguous for API calls that no Mapbox SDK can reach given the Turf conflict. The project already deviates in the same way with Static Images.

---

## 6. Tokens

Sources: [Token management guide](https://docs.mapbox.com/accounts/guides/tokens/), [API guides](https://docs.mapbox.com/api/guides/), Directions and Tilequery reference pages.

- **Scopes**:
  - Directions and Tilequery only require "A valid Mapbox access token". No specific scope is listed.
  - The map itself needs `styles:read` and `fonts:read` ("To display a map in a web or mobile application, you should create a separate access token that does not include the private uploads-related scopes, but does include the public styles:read and fonts:read scopes").
  - `styles:tiles` is needed for Static Images.
  - Secret (`sk`) scopes are for uploads, tilesets and SDK downloads, none of which applies here.
- **Embedded public token**: the existing app `pk` token works for Directions and on-device terrain.
  - **URL restrictions do not protect it.** Among unsupported cases, the docs list "Requests from mobile applications built with the Mapbox Maps or Navigation SDKs". Restrictions are referer-based, so they cannot apply to a native `URLSession` call either.
  - Mitigations: a dedicated token per feature, usage monitoring, and rotation.
- **Rate limits are per token**, so a **dedicated Directions token** (separate from the map or Static Images token) keeps the 300/min Directions budget isolated and makes usage per feature visible.
- **Server token**: needed only if the backend calls Mapbox, for example to recompute at save time or to decode Terrain-RGB server side. Use a dedicated public-scope token without URL restriction, following the pattern of ADR-029's `MAPBOX_GEOCODING_TOKEN`. Proxying every drag through the backend would hide the token but adds latency to each edit and runs into §2.8.1's "proxying" wording for map content.

---

## Open points for the driving session

- **Main decision**: storage policy for Itineraries. Options: (a) Waypoints only, compliant; (b) deliberate deviation as in ADR-029; (c) non-Mapbox router. This decision drives offline viewing, list thumbnails and the cost of displays.
- The Waypoint cap of 25 per request: enforce it in the UI, or split into several requests.
- Elevation through `elevation(at:)` requires 3D terrain on the edit map and the whole Itinerary in view. Accept that, or choose another source.
- Directions client on iOS: REST (simple, Swift 6 clean, §2.9.1 ambiguity) vs the Nav SDK `MapboxDirections` module (official, ties MapboxMaps to an exact version).
- Unconfirmed: whether Maps SDK MAUs cover Terrain-DEM tiles (not stated explicitly), and the Tilequery-on-Terrain-RGB contradiction.
