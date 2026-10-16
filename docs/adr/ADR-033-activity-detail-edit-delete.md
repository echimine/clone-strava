# ADR-033: Activity detail, edit and delete

- **Status**: accepted
- **Date**: 2026-10-16
- **Deciders**: echimine
- **Tags**: activities, feed, mobile, ios, api, privacy, realtime

## Context

The feed shows processed Activities as cards (ADR-029), but tapping a card does nothing, and an Activity cannot be changed once processed. The athlete needs to open an Activity, see it in full, fix its metadata (a ride saved as a run, a default title), and delete it.

The decisions were worked out in a grilling session on 2026-10-16. The facts they depend on, from the code at `f45b452`:

- `GET /v1/activities/:id` is **author only** and returns a thin `activityDetailSchema` (no map, place, author or engagement). `DELETE /v1/activities/:id` only accepts `pending` and `failed` Activities, `409` otherwise (ADR-031 §13). There is no `PATCH`.
- `get-visible-activity.use-case.ts` already holds the non-author visibility rules (owner always; others only `processed` and not `private`; `followers` for accepted followers). Only kudos use it.
- `activity` has no `updated_at`. `activity_import.activity_id` is `ON DELETE SET NULL`; the original file at `imports/{userId}/{importId}/source.{format}` is "kept indefinitely" (ADR-028); today's delete only removes `activities/{userId}/{activityId}/trace.json.gz`.
- The sport changes the official values: `clean-trace` drops points above a sport-specific plausible speed (run 12 m/s, ride 35 m/s), and `min_duration_s` / `min_distance_m` are per sport. `process-activity` only runs on an Activity in `processing`.
- **Follows** (no endpoints, `FollowUserUseCase` is a stub) and **Segments / leaderboards** (`match-segments`, `recomputeLeaderboard` are stubs) are not implemented. In practice the feed only shows the viewer's own Activities.
- On iOS, the feed has no GRDB cache (ADR-031 §14); `FeedView` has no navigation on cards; the Itinerary detail (ADR-030) is the closest pattern (`ItineraryDetailPage`, `ItineraryManageMenu`).

Vocabulary is in `CONTEXT.md` (**Activity**, **Official values**, **Provisional values**).

## Decision

### Overview

```
Feed card (processed) ──tap──► Activity detail ──"⋯" (author)──► Modifier ─► edit sheet ─► PATCH
        │                          │                         └─► Supprimer ─► confirm ─► DELETE
        └──long press (author)──► Modifier / Supprimer (same sheet and confirmation)
```

Kudos, comments and live updates on the detail are in [ADR-034](ADR-034-activity-engagement-and-live-detail.md).

### 1. Opening the detail (iOS)

- Tapping a **processed** card outside its buttons opens the detail. The comment button opens the detail scrolled to the comments with the composer focused (ADR-034). The kudos button stays a toggle.
- **Local cards** (not yet processed or `failed`, ADR-031 §14) are not tappable and keep their own Retry / Delete menu.
- Long press on **one of my** processed cards: context menu "Modifier" (opens the edit sheet over the feed) and "Supprimer" (confirmation). No menu on other athletes' cards.

### 2. `GET /v1/activities/:id` for every visible Activity (amends ADR-031 §13)

- Open to any viewer who can see the Activity, through `getVisibleActivity` (rules above). Not visible or unknown: `404 activity_not_found`.
- The author keeps seeing their Activity **in any state** with `processingStatus` and `processingError`: the app's resync of Activities in `processing` relies on it (ADR-008 §6). Other viewers only ever get `processed` Activities.
- Response (`activityDetailSchema`, contracts → OpenAPI → Swift, ADR-026): `id, title, description, sportTypeCode, startedAt, endedAt, visibility, processingStatus, processingError, locationName, stats {distanceM, movingTimeS, elapsedTimeS, elevationGainM, avgSpeedMs, maxSpeedMs, avgHeartRate, maxHeartRate, calories} | null, map {polyline, precision: 5} | null, author {id, displayName, avatarUrl}, engagement {kudosCount, commentCount, viewerHasKudoed}, viewerIsAuthor, updatedAt`.
- Assembled like the feed (ADR-029 §2): `activities` returns the Activity with its stats and track fields; **`apps/api`** adds the author (`users` + `auth` fallback) and engagement through the same assembler, since `activities` may not call `engagement` (ADR-021 §2).

### 3. Detail screen (iOS)

- **Map**: an interactive Mapbox `MapView` (pan, zoom) drawing `map.polyline`, camera fitted to its bounds, start and end pins. No new trace endpoint: the privacy-zoned polyline of ADR-029 §3 is enough.
- **Header**: author avatar and name (not tappable: no athlete profile exists), relative date, sport, place.
- **Title and description** (description hidden when empty).
- **Stats grid**: a stat is shown only when it is not null **and** the sport tracks it (`tracksDistance`, `tracksElevation`); pace or speed follows the sport's `paceUnit`; heart rate and calories only when present. Formatting reuses `ActivityCard`'s.
- **Toolbar "⋯"** for the author only: "Modifier", "Supprimer" (destructive).
- **States**: loading, error with retry, and **unavailable** — when the Activity is deleted or no longer visible while open (`404` on reload, or the realtime events of §8 and ADR-034), the content is replaced by an empty state "Cette activité n'est plus disponible" with a "Retour" button. The screen is never closed by force.

### 4. `PATCH /v1/activities/:id`

- **Body**: any non-empty subset of `title` (1–255, trimmed), `description` (≤ 10,000, `null` or empty clears it), `sportTypeCode` (an active `sport_type`), `visibility` (`public` / `followers` / `private`). Same limits as `createActivityRequestSchema`. Empty body: `422`.
- **Who**: not visible: `404`; visible but not the author: `403 not_activity_author`.
- **When**: `processed` only; other states: `409 activity_not_editable` (the finish screen and import sheet already set these fields before processing).
- **Sport change**: the official values must meet the new sport's minimums (`moving_time_s ≥ min_duration_s`, and `distance_m ≥ min_distance_m` for GPS sports), otherwise `422 activity_too_short_for_sport`.
- **Write**: one `UPDATE`, setting the new `activity.updated_at`. Last write wins; no version check (the author is the only editor, ADR-008 "Alternatives").
- **Response**: `200` with the full detail of §2.
- **After the commit**: domain event `activities.activity.updated` `{ activityId, userId, changedFields }` (ADR-021 §3), and the reprocessing job of §5 when the sport changed.

### 5. Silent reprocessing after a sport change

Fixing the sport is the main reason to edit (a ride saved as a run lost every point above 12 m/s), so the official values are recomputed.

- The `PATCH` use case enqueues **`reprocess-activity`** on the `activities` queue right after the commit (a must-happen reaction, ADR-021 §3), job id `reprocess-{activityId}-{updatedAt epoch ms}` so a replay is deduplicated and a later sport change gets its own job.
- The job reads the stored trace, runs the same steps as `process-activity` (clean with the new sport's plausible speed, metrics, privacy zone, polyline, place name) and upserts `activity_stats` and `activity_track` in one transaction. **`processing_status` stays `processed`** throughout: the card and the detail keep the old values until the new ones land.
- It records the sport it computed for in a new column `activity_stats.computed_for_sport_type_code`. The job is a no-op when that column already equals `activity.sport_type_code`.
- **Failure**: BullMQ retries with backoff; after the last attempt the old values stay, the error is logged, and nothing changes for the athlete (no `failed` state for a processed Activity).
- **Reconciliation**: the existing recurring reconciliation (ADR-019 §7) also enqueues `reprocess-activity` for processed Activities whose `computed_for_sport_type_code` differs from `sport_type_code` (covers a crash between commit and enqueue).
- **Success**: emits `activities.activity.updated` with `changedFields: ["stats"]`.

### 6. `DELETE /v1/activities/:id` for processed Activities (amends ADR-031 §13, ADR-028)

- **Allowed** on `pending`, `failed` and now **`processed`**. `processing` stays `409 not_deletable` (the worker is writing it; the app already handles this case, ADR-031 §14).
- **Who**: not visible: `404`; visible but not the author: `403 not_activity_author`.
- **Hard delete** (ADR-017): one `DELETE` of the row; stats, track, kudos, comments and segment efforts go by cascade. `activity_import` keeps its row with `activity_id = null`, so the history stays and the same file can be imported again (the importer already releases the content hash of an import whose Activity is gone).
- **Storage, after the commit**: delete the trace `activities/{userId}/{activityId}/trace.json.gz` **and**, for an imported Activity, the original file `imports/{userId}/{activityId}/source.{format}` (the import id is the Activity id, ADR-028 §1). A storage failure is logged and does not fail the request, as today.
- **After the commit**: domain event `activities.activity.deleted` `{ activityId, userId }`.
- `204`; a second `DELETE` gets `404`.

### 7. iOS: edit, delete, and the feed

- **Edit sheet**: a `NavigationStack` + `Form` sheet (same style as `ImportConfirmationSheet`): title, multi-line description, sport picker, visibility picker; "Annuler" and "Enregistrer", disabled while the title is blank. Opened from the detail's "⋯" and from the card's context menu.
- **Delete**: `confirmationDialog` "Supprimer cette activité ? Cette action est irréversible.". From the detail: back to the feed, the card is gone, no toast. From the card's menu: the card leaves with an animation.
- **Online and optimistic, no sync queue** (amends ADR-008 §1, §3): the change shows at once (sheet closed, values or card updated), then the request is sent; on failure the previous state comes back with an error toast, and the sheet reopens with the athlete's input on a validation error (`422`). Offline, the request fails like any other. Neither the feed nor the detail is cached in GRDB, so a persistent queue would almost never be useful.
- **The feed follows the detail**: when the athlete comes back from the detail, the card reflects what changed there (title, sport, visibility, stats after reprocessing, kudos and comment counts, deletion). The detail publishes its changes on a small Core-level change stream that `FeedStore` applies; features still never import each other (ADR-007), the app shell wires both.
- **Code**: a new `Features/ActivityDetail` (page, store, edit sheet, manage menu, repository); the feed receives `openActivity`, `editActivity` and `deleteActivity` closures from the app shell.

### 8. Realtime on the owner's topic (amends ADR-010, ADR-021 §4, §5)

The bridge forwards the new domain events on `user:{userId}`, so the author's other devices stay in step:

| Domain event | Mobile event | Payload |
|---|---|---|
| `activities.activity.updated` | `activity.updated` | `{ activityId, changedFields }` |
| `activities.activity.deleted` | `activity.deleted` | `{ activityId }` |

- `activity.updated`: the feed reloads that card's data and an open detail reloads; the echo of the device's own write is harmless (same data).
- `activity.deleted`: the card goes, an open detail switches to the unavailable state.
- ADR-034 adds the `activity:{id}` topic to both events for other viewers.

### 9. Segments, later

Segments and leaderboards are stubs, so nothing is recomputed now. When they are built:

- a visibility change (to or from `private`) must recompute the leaderboards of the Activity's segments, since `segment_effort.rank` is stored;
- a sport change must delete the Activity's efforts and run `match-segments` again (segments have a sport);
- a delete removes the efforts by cascade and must recompute the ranks of the segments they were on.

These are must-happen reactions: the `activities` use cases (or `reprocess-activity`) enqueue the jobs, not a listener of `activities.activity.updated` / `deleted` (ADR-021 §3).

### 10. Out of scope

Photos and videos (`activity_attachment`); charts, splits, streams, elevation profile; trimming the trace or correcting measured values; athlete profiles and tappable athletes; follows; sharing (the card's button stays a placeholder); persistent offline queue for edit and delete; segment recomputation (§9); backoffice `ActivityDetail` / `useDeleteActivity` (ADR-013); PostHog events for edit and delete; live updates in the feed for other athletes' Activities.

## Alternatives Considered

| Option | Why not |
|---|---|
| Soft delete with "Annuler" or a trash | A `deleted_at` filter in every activity query (feed, profile, stats, visibility) for an undo nobody asked for; ADR-017 keeps soft delete for comments only |
| Persistent `update_activity` / `delete_activity` queue (ADR-030 pattern) | The detail needs the network anyway (no cache), so the queue would almost never run; a queue also needs a local copy of the Activity to apply pending changes to |
| Sport change as a label only | Leaves wrong official values, which is the very mistake the athlete is correcting |
| Visible reprocessing (back to "Traitement…") | The Activity would leave the feed of other athletes (`processed` only) and the card would flicker for a few seconds of work |
| Enqueue reprocessing from a listener of `activities.activity.updated` | A lost event would leave wrong values forever (ADR-021 §3) |
| Keep the original import file after a delete | The athlete expects their data gone; the file was only kept to reprocess an existing import |
| Static map image in the detail | The detail is where panning and zooming on the trace is worth the `MapView` cost the feed avoids |
| Edit on a pushed page | A sheet is lighter for four fields and works the same from the feed's context menu |

## Consequences

### Positive
- One read path for every viewer, with the visibility rules already used by kudos.
- The edit and delete flows are online-only and optimistic, like kudos: no new local state machine.
- A wrong sport is fully corrected (official values and, later, segments) without the Activity ever leaving the feed.
- Deleting removes everything stored for the Activity, including the original file.

### Negative / Risks
- **Orphan files** if storage deletion fails after the commit: logged only, no sweeper.
- **No undo**: a mistaken delete is final.
- **Reprocessing re-reads the trace and re-geocodes**: one Mapbox geocoding request per sport change (ADR-029 §4 quota).
- **Followers rules untested in practice**: follows do not exist yet, so other viewers never reach the detail until they do.
- **Segment rules written but not enforced** until segments exist (§9).

## References
- [ADR-029: Activity feed and activity card](ADR-029-activity-feed-and-card.md)
- [ADR-030: Itineraries on iOS](ADR-030-itineraries-on-ios.md) (detail and manage-menu pattern)
- Mapbox Maps SDK for iOS, camera for coordinates: https://docs.mapbox.com/ios/maps/guides/camera-and-animation/camera/

## Links

- **Depends on**: [ADR-019](ADR-019-activity-creation-flow.md), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-029](ADR-029-activity-feed-and-card.md), [ADR-031](ADR-031-live-recording-on-ios.md)
- **Amends**: [ADR-008](ADR-008-mobile-offline-sync.md) (§1 detail read from the API, §3 no queue for edit and delete of processed Activities), [ADR-010](ADR-010-backend-realtime.md) (`activity.updated`, `activity.deleted` events), [ADR-017](ADR-017-data-model.md) (`activity.updated_at`, `activity_stats.computed_for_sport_type_code`), [ADR-019](ADR-019-activity-creation-flow.md) (§9 `GET` and `DELETE`, §7 reconciliation also covers reprocessing), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (§5 `reprocess-activity` job, `activities.activity.updated` / `deleted` events), [ADR-028](ADR-028-activity-import-from-file.md) (original file deleted with its Activity), [ADR-031](ADR-031-live-recording-on-ios.md) (§13 `GET` for visible Activities, `DELETE` of processed Activities)
- **Related**: [ADR-007](ADR-007-mobile-architecture.md), [ADR-026](ADR-026-openapi-swift-codegen.md), [ADR-030](ADR-030-itineraries-on-ios.md), [ADR-034](ADR-034-activity-engagement-and-live-detail.md)
