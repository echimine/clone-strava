# ADR-029: Activity feed and activity card

- **Status**: accepted
- **Date**: 2026-10-02
- **Deciders**: echimine
- **Tags**: activities, feed, engagement, kudos, maps, geocoding, mobile

## Context

Imported (ADR-028) and recorded (ADR-019) activities are processed by the worker, but nothing shows them: the Home tab is a placeholder, there is no read endpoint for activities, and the ADR-021 §6 feed building blocks (`social.getFolloweeIds`, `users.getSummaries`, `engagement.getCounts`) were stubs.

The Home feed shows one card per activity, reused later on the profile screen:

- author full name and avatar;
- relative start date ("Aujourd'hui à 14:32"), sport and place ("Annecy, Haute-Savoie");
- distance, elevation gain, moving time;
- a map with the GPS trace;
- kudos (like), comments and share.

Several things the card needs do not exist: a place name, a map image of the trace that is cheap to render in a scrolling list, author names (no `user_profile` row is ever created), and kudos.

## Decision

### 1. `GET /v1/feed`

- **Content**: the viewer's own `processed` activities (any visibility) plus the `public` and `followers` activities of **accepted** followees. Pending follows, private activities and activities still in processing are excluded.
- **Pagination**: keyset on `(started_at desc, id desc)` through an opaque cursor (base64url of `startedAt|id`), `?cursor=&limit=` (1–50, default 20), `nextCursor: null` on the last page. Page numbers (`common/pagination.ts`) would duplicate or skip items when activities are inserted while scrolling. An invalid cursor is `422 invalid_cursor`.
- **Response item**: `id, title, sportTypeCode, startedAt, visibility, locationName, stats {distanceM, movingTimeS, elapsedTimeS, elevationGainM}, map {polyline, precision: 5} | null, author {id, displayName, avatarUrl}, engagement {kudosCount, commentCount, viewerHasKudoed}, viewerIsAuthor` (`packages/contracts/src/activities/feed.ts`).

### 2. Where the feed is assembled

ADR-021 §6 steps 1–2 (followees, then a page of activities with stats and map fields from the module's own tables) run in `activities` (`GetFeedPageUseCase`). Steps 3–4 (authors, engagement) run in **`apps/api`** (`FeedAssembler`), because `activities` (layer 2) may not call `engagement` (layer 3). The assembler is reused by every activity list (profile next).

**Author names**: `user_profile` names win; otherwise Better Auth's `user.name` / `user.image`, read through a new batch method `AuthService.getPublicIdentities(ids)` (`auth` owns that table). Profile creation is a separate topic.

### 3. Map: static image from a precomputed polyline

- The worker stores `activity_track.map_polyline`: the Google polyline5 of the **privacy-zoned** route, simplified with growing Douglas-Peucker tolerances (5 m, 10 m, 20 m…) until it fits **2,000 characters**. A Mapbox Static Images URL is limited to 8,192 characters, and some polyline characters triple when percent-encoded. Migration 0005 backfills existing rows with PostGIS `ST_AsEncodedPolyline`.
- The app builds a Mapbox Static Images URL (`outdoors-v12`, orange `path`, start/end pins) with its public token and caches the image (memory + HTTP disk cache). An interactive `MapView` or a `Snapshotter` per cell would be far heavier in a scrolling list.

### 4. Place name: server-side reverse geocoding

`process-activity` reverse-geocodes the first point of the privacy-zoned route with Mapbox Geocoding v6 (`types=place,locality`, `language=fr`) and stores `activity_track.location_name` as `"{place}, {region}"`. It runs in a new `geocoding` platform module, outside the processing transaction, with a 3 s timeout; any failure stores `null` and never fails processing. Without `MAPBOX_GEOCODING_TOKEN` (a dedicated server-side token with default public scopes and no URL restriction, distinct from the app's token) the module is a no-op.

**Temporary vs permanent endpoint**: the permanent endpoint is the only one whose terms allow storing results, but it has no free tier (5 $ / 1,000 requests, sales contact required). This project is a non-commercial clone, not published: production uses the **temporary** endpoint (100,000 free requests per month) and stores the result anyway, a deliberate deviation from Mapbox's terms. `MAPBOX_GEOCODING_PERMANENT=true` switches to the permanent endpoint if the app ever ships.

### 5. Kudos

`PUT` / `DELETE /v1/activities/:id/kudos`, both idempotent, both returning `{ activityId, kudosCount, viewerHasKudoed }` so the app's optimistic update can reconcile. `404 activity_not_found` when the viewer cannot see the activity (owner, `public`, or `followers` for followers), `422 cannot_kudos_own_activity`. Comments are counted (non-deleted) but have no screen yet; share uses the iOS share sheet and is not counted.

### 6. Mobile

- The card lives in `Core/DesignSystem/ActivityCard/` with its model in `Core/Domain/Activities/`, because Feed and Profile may not import each other (ADR-007).
- `Features/Feed` owns `FeedStore` (refresh, infinite scroll, optimistic kudos) and reloads on the realtime `activity.processed` event (ADR-010), not on `activity_import.completed`, which fires while the activity is still processing.
- `APIClient` now decodes ISO 8601 dates with or without fractional seconds.

## Alternatives Considered

| Option | Why not |
|---|---|
| Page-number pagination | Duplicates or gaps when new activities arrive while scrolling |
| Reverse geocoding on iOS (`CLGeocoder`) | Repeated on every device, Apple rate limits, inconsistent names across users |
| Interactive Mapbox map or `Snapshotter` per card | Memory and GPU cost in a scrolling list |
| Mapbox Static Images rendered and stored by the worker (`map_thumbnail_url`) | Needs the `media` queue and storage (ADR-011, "later"); the URL approach needs neither |
| Assemble the whole feed in `activities` | Would make `activities` depend on `engagement`, breaking ADR-021 §2 layering |

## Consequences

### Positive
- The feed is four batch calls per module plus one per page for kudos state, whatever the page size.
- No geometry is read on the feed path; the card's map is a cacheable URL.
- The place name is computed once, on the privacy-zoned route, so it never reveals a hidden start.

### Negative / Risks
- **Geocoding terms**: storing temporary-endpoint results breaches Mapbox's terms; Mapbox may revoke the token, in which case place names become `null` (processing is unaffected). Must move to the permanent endpoint or a free dataset (e.g. GeoNames) before any public release. Activities processed before this ADR keep `location_name = null`.
- **Followee list in `IN (...)`**: fine for the MVP (ADR-021 "Negative"), a materialized feed later.
- **Public Mapbox token in image URLs**: normal for public tokens; it must be URL- and scope-restricted in the Mapbox dashboard.
- **Realtime only reaches the owner** (`user:{id}` topic): followees' new activities appear on pull-to-refresh.

## References
- Google encoded polyline: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
- Mapbox Static Images API: https://docs.mapbox.com/api/maps/static-images/
- Mapbox Geocoding v6 (reverse, `permanent`): https://docs.mapbox.com/api/search/geocoding/
- PostGIS `ST_AsEncodedPolyline`: https://postgis.net/docs/ST_AsEncodedPolyline.html

## Links

- **Depends on**: [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-019](ADR-019-activity-creation-flow.md), [ADR-028](ADR-028-activity-import-from-file.md)
- **Amends**: [ADR-017](ADR-017-data-model.md) (`activity_track.map_polyline`, `location_name`), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (§6 feed assembled in `apps/api`, `geocoding` platform module, auth identity fallback), [ADR-026](ADR-026-openapi-swift-codegen.md) (first documented response bodies)
- **Related**: [ADR-007](ADR-007-mobile-architecture.md), [ADR-008](ADR-008-mobile-offline-sync.md), [ADR-010](ADR-010-backend-realtime.md), [ADR-011](ADR-011-backend-worker.md), [ADR-027](ADR-027-user-location-on-maps.md)
