# ADR-039: Segments and Records in the app

- **Status**: accepted
- **Date**: 2026-11-05
- **Deciders**: echimine
- **Tags**: segments, records, best-efforts, medals, leaderboard, local-legend, premium, matching, postgis, openstreetmap, odbl, swimming, fit, ios, api, worker

## Context

Nervo has a `segments` module in name only: `segments.segment` has no creator nor verification, `segment_effort` stores a denormalized `rank`, the `match-segments` job throws `not implemented`, `matchSegment` is empty, and the iOS "Segments" screen is an unwired placeholder. Records do not exist at all: ADR-036 §11 put "Records, best efforts, results and medals" out of scope. The domain event `segments.efforts.matched` and its mobile event `activity.segments_matched` are wired but never emitted.

The decisions were worked out one ticket at a time on the map [Segments et Records dans l'app](https://github.com/echimine/clone-strava/issues/223) (4 research, 11 grilling and 5 prototype tickets). The facts they depend on:

- **Five sports only**: `run`, `ride`, `swim`, `walk`, `hike`. `swim` has no map in the app, and no pool swim can enter Nervo today: the import refuses a file without positions (`no_gps_data`, ADR-028), and the parser folds `swimming:lapSwimming` and `swimming:openWater` into `swim`.
- **The stored cleaned trace** (`trace.json.gz`, timestamps, Pauses) is the only timed source; `activity_track.route` is simplified (Douglas-Peucker 5 m) and cut by the privacy zone (ADR-019 §8, ADR-036 §5).
- **The privacy zone** removes the leading and trailing points that lie within `privacy_zone_radius_m` (default 200 m) of the first and last point, as the crow flies (`applyPrivacyZone`).
- **The Activity analysis** (ADR-036 §6) is versioned by `ACTIVITY_ANALYSIS_VERSION`, and the 10-minute reconciliation sweep already backfills lagging Activities, 100 at a time (ADR-036 §7). `compute` also redoes the Mapbox reverse geocoding on each pass.
- **Research**:
  - [Source mondiale des Segments créés par Nervo](https://github.com/echimine/clone-strava/issues/224): only OpenStreetMap (ODbL) covers the world, with no ready-made climbs; climbs must be computed with an elevation model (Copernicus GLO-30, IGN in France), with the public length × grade rule (Cat. 4 from a score of 8,000).
  - [Algorithme d'appariement des Segments et coût du rétro-appariement](https://github.com/echimine/clone-strava/issues/225): Strava matches on elapsed time with oriented start/finish lines and several efforts per activity; discrete Fréchet costs 2–64 ms per Segment; retro-matching is dominated by reading traces from the bucket.
  - [Calcul du meilleur temps sur une distance à partir d'une trace](https://github.com/echimine/clone-strava/issues/226): an O(n) two-pointer window on cumulative distance, with interpolation, under 1 ms per Activity.
  - [Natation en piscine : données disponibles pour des Records](https://github.com/echimine/clone-strava/issues/227): only FIT carries lengths (`length` messages, `session.pool_length`); a pool Record is the best sum of N consecutive active lengths.
- The UI follows Strava, from reference screenshots: a "Résultats" card before the Splits, ribbon medals "PR / 2 / 3", "Performances" on the Activity card.

## Decision

### 1. Vocabulary

The glossary (`CONTEXT.md`) gains or rewrites **Segment**, **Verified segment**, **Effort**, **Leaderboard**, **Local Legend**, **Record**, **Best effort**, **Medal**, **Premium**, **Paywall** and **Report**. The labels shown in the app follow Strava; the domain terms do not change:

| Domain term | Shown in the app |
|---|---|
| Best effort | « meilleur effort » (« Meilleurs efforts » for the list) |
| Medal | « Médaille »; their count is « Performances »; a Segment's gold reads « Record personnel » (« PR » on the ribbon) |
| Leaderboard | « Classement » |
| Local Legend | « Légende locale » |
| Verified segment | « Segment vérifié » |

### 2. Modules and boundaries (amends ADR-021 §1, §2, §5, §7)

- **`activities`** owns Best efforts, their Medals and the pool data (§4, §5). Records are read from it; there is no Records module.
- **`segments`** owns Segments, Efforts, their Medals, favourites, matching and the Leaderboard. It now depends on `activities`, `sports` **and `users`**.
- **Published read views**. A module may publish a **SQL view in its own schema** as a read contract; another module may join that view, and only that view, in read-only queries. The owner decides what the view exposes and keeps it stable. Two views are published:
  - `activities.leaderboard_activity (id, user_id, sport_type_code, visibility)`;
  - `users.leaderboard_athlete (user_id, gender, birth_date, weight_kg, privacy_zone_radius_m)`.

  `segments` joins them to build the Leaderboard, the Local Legend and the map cards in one SQL query. A copy kept in `segments` by events was rejected: a lost event on a visibility change would leak a private Activity into a Leaderboard.
- **Matching** never reads `activity_track`, `user_profile` nor the bucket: `ActivitiesService` exposes "matching trace of an Activity" (cleaned points, Pauses, sport, author, start and end point) and "Activities of a sport near a path" (cursor-paginated).
- **`apps/api` composes**, as for the feed (ADR-029 §2) and the viewer filter (ADR-038 §7): it resolves Premium (`subscriptions`), the `ViewerExclusions`, and the followee ids (`social`), then passes them to `segments` as parameters. `segments` never depends on `subscriptions` nor `social`.

### 3. Records and Best efforts (amends ADR-036 §6, §7, §11; ADR-033 §5)

- **Distances** (in code, `activities/domain`), never miles except where named:

  | Record set | Distances |
  |---|---|
  | `run` | 400 m · 1 · 2 · 3 · 5 · 10 · 15 · 20 km · half marathon (21.0975 km) · 30 km · marathon (42.195 km) · 50 · 100 km |
  | `ride` | 5 · 10 · 20 · 30 · 40 · 50 · 80 · 100 · 150 · 160 (100 miles) · 200 km |
  | `walk` | 1 · 2 · 3 · 5 · 10 km · half marathon · 20 · 30 km · marathon |
  | `hike` | 5 · 10 · 15 · 20 · 30 · 40 · 50 km |
  | `swim_pool` | 50 · 100 · 200 · 400 · 800 · 1,000 · 1,500 m, only multiples of the pool length; no Record for a pool in yards |
  | `swim_open_water` | 400 · 750 m · 1 · 1.5 · 1.9 · 3.8 · 5 · 10 km |

  The two swimming sets are never compared. A swim with a GPS trace is open water; a swim with pool lengths is a pool.
- **Computation**, in the Activity analysis, on the cleaned trace before the privacy zone:
  - **elapsed time**, every Pause included, from any point of the Activity (not tied to Splits);
  - a two-pointer sliding window on cumulative distance, **interpolated** at both ends (the minimum falls either on a window ending on a point or starting on one);
  - a window holding a **gap of more than 30 s** between two points outside a Pause is discarded (**60 s** in open water); a Pause is not a gap;
  - pool: the best sum of N consecutive **active** lengths with N × pool length = distance; a rest length breaks the sequence;
  - no trace (or no lengths) means no Best effort; a distance longer than the Activity is absent, never extrapolated.
- **Every Activity counts, whatever its visibility.**
- **Storage**: `activities.best_effort`, one row per (Activity, distance), upserted by `save` in the processing transaction (§17). The **Record** is the minimum read over the athlete's non-removed Best efforts; nothing else is stored.
- **Removing a Best effort** (`DELETE /v1/activities/:id/best-efforts/:distanceM`, author only): sets `removed_at`, **for good**. A recomputation updates the time but never brings back a removed row. Medals are replayed (§8).
- **History**: `ACTIVITY_ANALYSIS_VERSION` becomes **2**; the existing sweep recomputes every processed Activity at 100 per 10 minutes, silently (no event).
- **Fix**: when only the analysis lags (the sport did not change), `reprocess-activity` **does not redo the reverse geocoding** and keeps the stored place name.
- Ties between Best efforts are judged **to the millisecond**.

### 4. Pool swimming imported from FIT (amends ADR-028)

- A FIT file with `sub_sport = lap_swimming` is **accepted without positions**: an Activity `swim` with no `activity_track`, no map and no Segments.
- `@repo/track-files` reads `lengthMesgs` (start, `totalElapsedTime`, `lengthType` active/idle) and `sessionMesgs[0].poolLength` / `poolLengthUnit`, and keeps the sub-sport.
- **Official distance** = active lengths × pool length. The lengths are stored **in the stored trace** (`trace.json.gz` gains `lengths`), which the analysis already rereads; the pool length goes to `activity.pool_length_m` (null = not a pool).
- A pool in yards is imported (distance converted) but has no Record. TCX, GPX, the iPhone Recording and Apple Health give no pool swim (Apple Health is out of scope).
- Pool swims refused before this change must be imported again.

### 5. Segments (amends ADR-017, ADR-030)

- **A Segment has one sport** among those with a map: `run`, `ride`, `walk`, `hike`. A climb for both bike and run is two Segments.
- **Always public**; its creator is **never shown**. Created by an athlete (**drawn** on the map) or by **Nervo** (§10); the app never tells them apart. Provenance: `origin` (`athlete` | `nervo`) and, for Nervo, a unique `source_key`. There is no "Nervo" system user.
- **Creation by an athlete**, checked by the app and again by the server:
  - drawn with the **Itinerary editor** (ADR-030: Waypoints, Legs on Mapbox Directions `walking` or `cycling`, or straight); the Mapbox path is stored under the same waiver as Itineraries;
  - length **≥ 200 m on foot, ≥ 500 m by bike, ≤ 50 km**; start and finish **≥ 100 m apart** (no loop);
  - **duplicate refused** when an existing Segment of the same sport matches it **both ways** (`matchSegment` of each on the other); a shorter Segment inside a longer one is allowed;
  - name required, **3–60 characters** after trimming, no uniqueness, no default;
  - **10 Segments per athlete per rolling 24 h**, no total cap.
  - Extracting a Segment from one's own Activity was prototyped and **dropped**.
- **Computed once by the server** at creation, through the `ElevationService` (IGN, Open-Meteo fallback), never from the creator's GPS altitude: distance, elevation gain, average and maximum grade, low and high altitude, elevation profile (`path` becomes a **LineStringZ**), and the **climb category** (4, 3, 2, 1, HC) with the length × grade rule; no category under a score of 8,000.
- **After creation**: the creator renames it at any time; deletes it **while nobody else has an Effort on it**; the path is never editable. A created Segment is **starred** for its creator.
- **Verified segment**: a mark granted and withdrawn by an Administrator (`verified_at`), with the same Leaderboard and rules; the creator keeps their rights; it stays verified when renamed; a Nervo Segment starts unverified.
- A Segment with **no creator** (Nervo, or creator's account deleted) is renamed or deleted only by an Administrator, with a mandatory reason, and **not as a Sanction** (no athlete, no e-mail).
- **Favourites** (star): private, free, listed in Plus › « Segments ».

### 6. Matching (amends ADR-019 §8, ADR-033 §9, ADR-038 §16)

- **`matchSegment`**, pure TypeScript in `segments/domain`, returns a **list** of Efforts for one trace and one Segment:
  1. detect the **oriented crossings** of virtual start and finish lines, perpendicular to the Segment;
  2. for each start, take the first finish after it and check, on the portion resampled every 10 m, **coverage** (≥ 90 % of the Segment's points within 25 m) and **order** (discrete Fréchet ≤ 50 m);
  3. reject gaps, including a move during a Pause;
  4. **interpolate** the instant of each crossing (a deliberate deviation from Strava).

  Thresholds are starting values, to calibrate on fixtures.
- **Several Efforts per Activity**, even on the same Segment (a loop ridden three times gives three Efforts). Time is **elapsed time**, Pauses included, rounded to the second.
- **Matched on the stored cleaned trace**, before the privacy zone. Each Effort stores how close it comes to the Activity's start and end (the smallest crow-fly distance from its points to the Activity's first and last point). An Effort is **in the privacy zone** when either distance is below the athlete's **current** radius, **decided at read time**: a radius change replays nothing. This is slightly more protective than the cut of the route itself.
- **SQL only for the indexed prefilter** (degrees, overestimated margin); the exact test is in TS, in metres. For one Activity: Segments whose start and end are near the cleaned trace, passed as a parameter. For one Segment: Activities whose route passes near its start and end, with a margin of 2 × the default zone radius.
- **`match-segments` is idempotent and complete**: it recomputes every Effort of the Activity, inserts the new ones, keeps those that still exist, deletes those that disappeared, writes `segments.activity_matching (version, matched_at)`, replays the Medals of the touched (athlete, Segment) pairs, then emits `segments.efforts.matched`.
- **Triggers**: a new Activity (after `process-activity`, as today); **a sport change** (end of `reprocess-activity`, which does not trigger it today); the Nervo import; and **a new algorithm version**: `SEGMENT_MATCHING_VERSION` is stored per Activity in `activity_matching`, and a sweep enqueues the lagging Activities. A **visibility change** triggers nothing.
- **Verdicts are kept**: when matching is replayed, a new Effort **inherits the status** (`suspicious` or `rejected`) of the old Effort of the same (Activity, Segment) pair whose time interval overlaps it the most; an old Effort with no successor goes with its verdict. Accepting (`valid` for good) is inherited too.
- **Suspicious effort** (ADR-038 §16), with maximums limited to the five real sports: `run` 25 km/h, `walk` and `hike` 10 km/h, `ride` 80 km/h. Efforts of `private` Activities are not checked.

### 7. Retro-matching

- **At the creation of a Segment by an athlete**: every Activity of its sport, **whatever their visibility, the whole history**. First the creator's Activities at once, then everyone else's by pages of 200 (`match-segment-history`, chained by cursor, deterministic job id without `:`) at a **lower priority** than `match-segments`. After each page, the Medals of each touched athlete on that Segment are replayed. The last page sets `segment.history_matched_at`; until then the Segment sheet shows « Recherche des Efforts passés sur ce Segment… ». A deleted Segment stops the next page. No guaranteed delay; minutes in practice.
- **Nervo import**: no retro-matching per Segment; `match-segments` is replayed **per Activity** of the sports with a map, at low priority, so each trace is read once and the prefilter finds all nearby Segments in one go.

### 8. Leaderboard, Medals and Local Legend

- **Leaderboard**: one line per athlete, their best Effort that **stands**: of a **public** Activity, **outside the privacy zone**, **not rejected** (a suspicious Effort stands, with no mark, and its athlete is not told). Elapsed time; **ties to the second** share the rank (1, 1, 3), the older Effort first. The **rank is computed at read time** for the viewer, after Blocks and Bans (ADR-038 §7); `segment_effort.rank` is dropped. The rank shows only on the Effort that forms the athlete's line.
- **Filters**: a sex selector (Tous / Hommes / Femmes) combined with **at most one** other filter:
  - a calendar period in the **viewer's** time zone (Aujourd'hui, Cette semaine from Monday, Ce mois-ci, Cette année), compared to the Effort's start, with each athlete's best Effort **within** the period;
  - Abonnements: athletes the viewer follows with an accepted Follow, plus the viewer;
  - an age band (≤ 19, 20-24, 25-34, 35-44, 45-54, 55-64, 65-69, 70-74, 75+) or a weight band (≤ 54, 55-64, 65-74, 75-84, 85-94, 95-104, 105-114, 115+ kg), from **current** values.

  Non-binary and undisclosed athletes are only in Tous; no weight, no weight band; no birth date, no age band. The rank is recomputed **within** the filter. There is no privacy setting to opt out.
- **Medals** (Efforts and Best efforts): gold, silver, bronze for the athlete's 1st, 2nd, 3rd fastest **at the date of the Activity**, counting all their Activities whatever the visibility, suspicious Efforts included, rejected Efforts and removed Best efforts excluded. The **first pass earns gold**; an equal time does not beat an earlier one and takes the next Medal. Medals are **stored** on the row and **replayed in date order** for the touched (athlete, Segment) or (athlete, record set, distance) whenever the athlete's history changes (Activity deleted, Effort rejected, sport changed, retro-matching, import of an older Activity, Best effort removed), **silently**, with no history and no notification. Whoever may see the Activity sees its Medals; Efforts in the privacy zone and their Medals are removed for everyone but the athlete. Medals are personal and never compare athletes.
- **Local Legend**: the athlete with the **most Efforts on the Segment over the last 90 rolling days**, counting only Efforts that stand, **one per Activity**; on an equal count, whoever **reached it first** keeps the title. Computed at read time, nothing stored; one for Tous, Hommes and Femmes, following the sex selector; the other filters do not change it. The Effort shows a laurel crown while its athlete **currently** holds the title.
- **Counters** (favourites, athletes, Efforts) are **not filtered** by Blocks and Bans (ADR-038 §7).

### 9. Premium (amends ADR-035 §6)

- **Only the Leaderboard is Premium**: beyond the top 10, and **every filter, the sex selector included**. Without Premium: the top 10 of Tous, the athlete's own line pinned under it (current rank and time, even beyond the 10th), then the insert « Voir le classement complet avec Premium ». An athlete already in the top 10 has no duplicate line.
- **Free**: Records, Medals, Local Legend (Tous only without Premium, since it follows the selector), favourites, creating Segments, the map, one's own Efforts and **own rank in Tous** everywhere, Verified segments. The Paywall text stays as is.
- **Gated by the server at read time** on `isPremium` (`subscriptions`), wired to RevenueCat or not: `GET /v1/segments/:id/leaderboard` answers the top 10, the viewer's line and `limited: true`; a filter, a sex other than Tous or a cursor answers `403 premium_required`. Nothing is stored: an expired Premium closes the Leaderboard at once. The app reads `isPremium` from `/v1/me` for the locks.
- **The Paywall opens from every lock**, as a sheet, as many times as tapped (the insert and each locked filter); « Passer » closes the sheet; while purchases are not wired, « Démarrer l'essai » closes it without granting anything. `paywall_viewed` gains `entry` (`onboarding`, `segment_leaderboard`, `leaderboard_filter`). The notification primer is not shown on this path.

### 10. Segments created by Nervo and open data

- **Source**: OpenStreetMap paths + an elevation model (IGN RGE ALTI in France, Copernicus GLO-30 elsewhere, SRTM as fallback); no FABDEM, Open-Meteo, Strava nor Climbfinder data.
- **Generator**: a TypeScript CLI in the monorepo, run offline country by country (not on the VPS), reusing `packages/core` for the climb category and the both-ways duplicate test. Climbs from a trough to a summit, smoothed with hysteresis; kept when length × grade ≥ 8,000 (Cat. 4); `ride` = road climbs, `hike` = climbs to a named summit on paths up to `sac_scale=demanding_mountain_hiking`, `run` = a few short urban climbs (score ≥ 1,500) and road climbs runnable on foot, `walk` = nothing. Same length and loop rules as for athletes. Figures, profile and category come from the generator's elevation model (the `ElevationService` quotas would not follow). Names in French: « Col du Galibier depuis Valloire », else « Montée de <route> à <lieu> », from `name:fr` then `name`; no usable name, no Segment. Output: one NDJSON file per country. **Pilot: France.**
- **Import**: `pnpm segments:import <file>` against the target database over an SSH tunnel; idempotent on `source_key`; skips duplicates of an existing Segment of the same sport (the athlete's stays) and keys in `segments.excluded_source_key` (written when an Administrator deletes a Nervo Segment); runs only add Segments, never modify them, so a rename holds. Then the per-Activity replay of §7. Nothing is loaded from the backoffice.
- **ODbL**: every Segment, athletes' included, is offered under ODbL; Efforts and traces are not covered. A public, unauthenticated `GET /v1/open-data/segments.ndjson.gz` serves a file of **all** Segments (name, sport, path, figures, no creator, no Effort), regenerated weekly by a job. An athlete Segment is never snapped onto an OSM path by the server.
- **Attribution**: a « Sources des données » screen in Settings (OpenStreetMap/ODbL, Copernicus, IGN, Mapbox) and « Données © OpenStreetMap » at the bottom of a Segment sheet.

### 11. Cross lifecycle (amends ADR-038 §7, §9, §13)

- **Medals are personal**: nothing that happens to another athlete replays them. Everything compared between athletes (rank, Leaderboard, Local Legend) is computed at read time with the viewer filter.
- **Block**: each disappears from the other's Leaderboard, top 10 and Local Legend, recomputed without them; Segments stay visible.
- **Ban**: while active, the athlete's Efforts leave Leaderboards and Local Legends, and come back at its end. Matching continues; nothing is deleted nor replayed.
- **Account deletion**: Efforts, Best efforts, Medals and favourites go by cascade. Just before the cascade, `apps/api` (`account-deletion`) deletes the Segments the athlete created **that nobody else has an Effort on** (a running retro-matching does not count); the others stay with `created_by = null`. Nothing is replayed for other athletes.
- **Segment deletion** (creator or Administrator): final and cascading (Efforts, favourites, verdicts); its Report cases close as « Cible supprimée »; the running retro-matching stops. Other athletes are not told; the creator gets the Sanction e-mail only when an Administrator deletes. Activities lose those lines in « Résultats » and their counters drop **at once** (counts are read, never stored). An open sheet shows « Ce Segment n'est plus disponible ».
- **Reports**: a Segment (name or path) can be reported through `POST /v1/reports` with `targetType: "segment"`. The case has **no target athlete** when the Segment has no creator. Reporting a Segment does **not** hide it from the reporter: it does not enter the viewer filter.

### 12. API

| Endpoint | Purpose |
|---|---|
| `GET /v1/activities/:id/results` | « Résultats »: `matchingInProgress`; `bestEfforts[]` (distance, time, Medal, first time, current Record); `efforts[]` (Segment id, name, distance, verified; time; Medal; first pass; rank on the athlete's line; Local Legend crown; `startPoint` for the ribbon on the map), in trace order. Privacy-zone Efforts removed for everyone but the author. Composed by `apps/api`. |
| `DELETE /v1/activities/:id/best-efforts/:distanceM` | Remove a Best effort for good (author) |
| `ActivityPost.medalCounts { gold, silver, bronze }` | « Performances » on the Activity card (feed, profile), Best efforts and Efforts added up per page by the assemblers, same privacy filter; no stored counter |
| `GET /v1/segments?bbox=&sport=&favorites=` | Map search: at most 50 Segments, `400 zone_too_large` beyond the extent of zoom 10.5. Per Segment: sport, name, verified, starred, distance, average grade, category, athletes, `myBestTimeS` else `leaderTimeS`, polyline |
| `GET /v1/segments/:id` | Sheet: figures, elevation profile, verified, starred and favourite count, `isMine`, `canDelete`, `historyMatching`, the viewer's Efforts (all visibilities, Medal, which one forms their line, rank), Local Legend Tous with the viewer's own 90-day count, top 10 + the viewer's line. Free. `404` once deleted |
| `GET /v1/segments/:id/leaderboard?gender=&filter=&value=&cursor=` | `{ limited, entries, me, localLegend }`; pages of 50, cursor `(time, date, id)`; `403 premium_required` (§9) |
| `POST /v1/segments/preview` | `{ sport, points }` → figures, profile, category, duplicate (with the existing Segment), quota left; nothing written |
| `POST /v1/segments` | Create: the server recomputes everything; `409 duplicate`, `429 quota`, `422` (length, loop, name); stars it; enqueues retro-matching |
| `PATCH /v1/segments/:id { name }` | Rename (creator) |
| `DELETE /v1/segments/:id` | Delete (creator), `409 has_other_efforts` |
| `PUT` / `DELETE /v1/segments/:id/favorite` | Star / unstar |
| `GET /v1/me/segment-favorites?cursor=` | Plus › « Segments » |
| `POST /v1/reports { targetType: "segment" }` | Report (existing endpoint; `ReportTargetReader` reads the Segment) |
| `GET /v1/open-data/segments.ndjson.gz` | Public ODbL file |

The backoffice endpoints (`segment.verify` / `unverify`, filters, no-creator rename and delete, Segment reports) are specified in [Segments et Efforts suspects dans le backoffice](https://github.com/echimine/clone-strava/issues/219).

### 13. Jobs (amends ADR-011, ADR-019 §8)

| Queue · job | Enqueued by | Notes |
|---|---|---|
| `segments` · `match-segments {activityId}` | end of `process-activity`, end of `reprocess-activity` when the sport changed, Nervo import, sweep | idempotent, complete; low priority from the import and the sweep |
| `segments` · `match-segment-history {segmentId, cursor}` | `POST /v1/segments`, then itself | pages of 200, lower priority |
| `segments` · `replay-segment-medals {userId}` | deleting an Activity (`activities` enqueues it after the commit) | replays all of the athlete's Segment Medals, since the touched Segments are unknown after the cascade; Best effort Medals are replayed in `activities` in the same use case |
| `segments` · `reconcile-segment-matching` (scheduler, every 10 min) | — | up to 100 processed Activities of the map sports with no `activity_matching` row or a lagging version |
| `segments` · `export-segments-odbl` (scheduler, weekly) | — | writes the public ODbL file to the bucket |
| `activities` · `reprocess-activity` | unchanged | analysis v2 (Best efforts, their Medals), no geocoding when only the analysis lags |

### 14. Realtime and the feed (amends ADR-029)

- **No new mobile event.** On `activity.segments_matched`, the feed and the profile list **reload the Activity** (so « Performances » counts Segment Medals), and the detail reloads `results`. The retro-matching banner refreshes when the sheet opens and on pull-to-refresh.
- **End of a Recording**: the celebration stays without Records (ADR-032 §5, §6 unchanged); nothing more after « Enregistrer », as on Strava. The card arrives with its Best efforts (`activity.processed`) and fills in with Segment Medals. Same for an imported Activity.

### 15. iOS

- **Map tab, two modes « Itinéraires | Segments »** (amends ADR-030), selector top left. The « Créer » button, top right in both modes, becomes a menu « Un Itinéraire / Un Segment ». The placeholder `SegmentsView` is deleted.
- **Segments mode**: the area shown at opening, then fixed, with « Rechercher dans cette zone » after a move; chips Tous / Vélo / Course / Marche / Randonnée and « Favoris »; under zoom 10.5, « Zoome pour voir les Segments » only; paths in dark grey; « n Segments dans cette zone » and a carousel of cards sorted by distance to the centre (sport icon, name, verified badge, star, distance · grade · category, athletes, « Mon record » else the leader's time); scrolling the carousel or tapping a path highlights it in orange; empty states. A card pushes the sheet.
- **Create**: sport first (with each sport's minimum, « Un Segment n'a qu'un sport »), the Itinerary editor with live figures and a disabled « Continuer » while a rule fails, then a **preview** screen (mini-map, full figures, profile, name with counter, « Créer le Segment »; duplicate with a link, and quota errors shown there), then « On cherche tes passages… » with « Voir mes Segments » and « Terminé ». Entries: the Map « Créer » menu and the « + » of Plus › « Segments ».
- **Segment sheet**: one scrolling page: back, name, ★ and count, ⋯ (« Signaler ce Segment »; « Renommer », « Supprimer » for the creator, Supprimer refused with an explanation once someone else has an Effort); map (orange, start and finish); name, sport, verified badge; distance, gain, grade, category; elevation profile; retro-matching banner; « Mes efforts » (« Mon record », « Mon rang », then every Effort newest first with its Medal, « Privée · hors Classement » when not public, an empty state); « Légende locale » (Tous); top 10 + my line; « Voir le classement »; « Données © OpenStreetMap ».
- **Leaderboard screen**, pushed: filter chips in one scrolling row (Tous / Hommes / Femmes, then Aujourd'hui, Cette semaine, Ce mois-ci, Cette année, Abonnements, « Âge ▾ », « Poids ▾ »); tapping another chip replaces the filter, tapping the active one removes it; the Local Legend on top follows the sex chip; rows with rank, Avatar, name, date, time, mine highlighted « (toi) »; my line pinned under the top 10; « Tu n'apparais pas dans ce filtre »; locks and the Premium insert without Premium.
- **Activity detail, « Résultats »** card just before the Splits: counters Meilleurs efforts · Segments · Performances (no Segments counter for a pool swim); up to 3 medalled lines, Best efforts first then Segments in trace order (title, time and pace: km/h by bike, /km on foot, /100 m in a pool; phrases « Nouveau record absolu ! », « Nouveau 2e record absolu ! », « Record personnel », « 2e meilleur temps », « · 1er passage »); « Afficher tous les résultats » pushes a screen with every Best effort and every Segment. While matching: « … » and « Recherche des Segments de cette Activité… ». **Ribbon medals** « PR / 2 / 3 », the same drawing everywhere. On the map, each medalled Segment gets its ribbon at its start with « Record personnel » and the Segment's name; overlapping labels hide each other. Long press on one's own Best effort: « Retirer ce temps de mes meilleurs efforts ».
- **Activity card**: a 4th value « Performances » (three ribbon medals and the count) after Distance, Allure, Temps; none without a Medal.
- **Profile**: Plus › « Segments » lists **my** starred Segments (sport, name, verified, distance · grade, my best time), with « + ». No Records section, no Local Legend line, nothing new on another athlete's profile.
- **Settings**: « Sources des données ».

### 16. Analytics

App events: `segment_created {sport}`, `segment_favorited`, `leaderboard_viewed {filter}`, `best_effort_removed {distance}`, and `paywall_viewed {entry}` (§9). No server event for Medals or Records.

### 17. Data model (amends ADR-017, ADR-021 §7)

| Table / view | Change |
|---|---|
| `activities.activity` | `pool_length_m real null` |
| `activities.best_effort` (new) | `activity_id` → activity cascade, `user_id`, `record_set` enum (`run`, `ride`, `walk`, `hike`, `swim_pool`, `swim_open_water`), `distance_m`, `elapsed_time_ms`, `start_distance_m`, `activity_started_at`, `medal` enum null (`gold`, `silver`, `bronze`), `removed_at`; PK `(activity_id, distance_m)`; index `(user_id, record_set, distance_m, elapsed_time_ms)` |
| `activities.leaderboard_activity` (view) | `id, user_id, sport_type_code, visibility` |
| `users.leaderboard_athlete` (view) | `user_id, gender, birth_date, weight_kg, privacy_zone_radius_m` |
| `segments.segment` | adds `created_by` → user `set null`, `origin` enum, `source_key` unique null, `verified_at`, `elevation_gain_m`, `max_grade`, `min_altitude_m`, `max_altitude_m`, `climb_category` enum null (`hc`, `1`–`4`), `map_polyline`, `history_matched_at`, `created_at`, `updated_at`; `path` becomes LineStringZ; GiST on `end_point` |
| `segments.segment_effort` | drops `rank`; adds `start_index`, `end_index`, `min_distance_to_activity_start_m`, `min_distance_to_activity_end_m`, `status` (ADR-038), `medal`; unique `(activity_id, segment_id, start_index)`; index `(segment_id, status, elapsed_time_s)` and `(user_id, segment_id, started_at)` |
| `segments.segment_favorite` (new) | `user_id` → user cascade, `segment_id` → segment cascade, `created_at`; PK `(user_id, segment_id)` |
| `segments.excluded_source_key` (new) | `source_key` PK, `excluded_at` |
| `segments.activity_matching` (new) | `activity_id` PK → activity cascade, `version`, `matched_at` |
| `moderation.report_target_type` | adds `segment`; `report_case.target_user_id` nullable for that target only |

Counts (athletes, favourites, Efforts, Medals per Activity) are always computed at read time.

### 18. Out of scope

- Segments live during a Recording; notifications (lost first place, new Record or Medal: APNs is not wired).
- First-place titles (« Roi/Reine de la montagne »); Local Legend stays.
- Replay (▶), sharing a Segment, « Analyser l'effort »; editing a Segment's path; extracting a Segment from an Activity.
- Creating a Segment from the backoffice; the backoffice screens themselves ([Segments et Efforts suspects dans le backoffice](https://github.com/echimine/clone-strava/issues/219)).
- New sports (trail, gravel, MTB, e-bike…); Apple Health; Records from manual entries; a Records section in the profile.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Joining other modules' tables directly | Breaks ADR-021 ownership: a column rename in `users` would silently break Leaderboards |
| A copy of visibility and athlete attributes in `segments`, kept by events | A lost event leaks a private Activity into a Leaderboard; the views give the same SQL with no sync |
| Stored, denormalized rank (ADR-017) | Blocks and Bans already make the rank per viewer; recomputing on every new Effort costs more than reading |
| Records in `jsonb` inside `activity_analysis` | Cannot index (athlete, distance, time) to read a Record or replay Medals |
| A Segments-only « Nervo » system user | Would appear in user lists, statistics and Follows, and could be banned |
| No interpolation at Effort or Best effort bounds (Strava) | Times would depend on sampling; interpolation is nearly free |
| Hausdorff distance for matching | Does not tell the right direction from the reverse or an out-and-back |
| Medals frozen at upload | Wrong after deletions, rejected Efforts or late imports; replaying in date order stays right |
| Records Premium, Local Legend Premium | Only the full Leaderboard sells; personal results stay free, matching the Paywall text |
| Extracting a Segment from an Activity | None of three prototyped interactions worked; drawing covers the need |
| A Segments layer that follows the camera, or a separate Segments screen | Prototyped; a mode of the Map tab with a fixed area reads better and bounds the load |
| Pool lengths in a new table | They are read only by the analysis, which already reads the stored trace |

## Consequences

### Positive

- One idempotent job (`match-segments`) covers new Activities, sport changes, Nervo imports and algorithm versions; one sweep catches what was lost.
- Everything compared between athletes is read-time, so Blocks, Bans, visibility and privacy-zone changes need no replay.
- Records reuse the Activity analysis and its backfill; no new pipeline.
- The views keep `segments` within ADR-021 while the Leaderboard stays one SQL query.

### Negative / Risks

- **Read-time Leaderboards** on popular Segments (tens of thousands of Efforts) need the indexes of §17 and may need a materialized best-per-athlete later.
- **Matching thresholds** are untested on real traces; false matches or misses until calibrated.
- **Retro-matching and the Nervo replay** read every trace of a sport from the bucket; slow on a large history.
- **ODbL** obliges publishing every Segment, athletes' included, for free.
- **Mapbox terms** (ADR-030 §1) now also cover drawn Segments; to fix before any public release.
- **Silent Medal rewrites** may surprise an athlete who remembers a gold.
- **Views are contracts**: changing one is a cross-module change.

## References

- Map and tickets: [Segments et Records dans l'app](https://github.com/echimine/clone-strava/issues/223)
- Research notes (throwaway branches): [nervo-segments-source.md](https://github.com/echimine/clone-strava/blob/research/nervo-segments-source/docs/research/nervo-segments-source.md), [segment-matching.md](https://github.com/echimine/clone-strava/blob/research/segment-matching/docs/research/segment-matching.md), [best-effort-from-trace.md](https://github.com/echimine/clone-strava/blob/research/best-effort-from-trace/docs/research/best-effort-from-trace.md), [pool-swim-records.md](https://github.com/echimine/clone-strava/blob/research/pool-swim-records/docs/research/pool-swim-records.md)
- Prototypes (never merged): `prototype/segment-creation`, `prototype/segment-map`, `prototype/segment-detail`, `prototype/activity-results`, `prototype/profile-records`
- Specs: [#246 Meilleurs efforts et Records](https://github.com/echimine/clone-strava/issues/246), [#247 Natation en piscine importée en FIT](https://github.com/echimine/clone-strava/issues/247), [#248 Appariement des Segments](https://github.com/echimine/clone-strava/issues/248), [#249 Créer un Segment dans l'app iOS](https://github.com/echimine/clone-strava/issues/249), [#250 Les Segments sur la carte](https://github.com/echimine/clone-strava/issues/250), [#251 Fiche d'un Segment, Classement et Légende locale](https://github.com/echimine/clone-strava/issues/251), [#252 Résultats d'une Activité et Performances](https://github.com/echimine/clone-strava/issues/252), [#253 Segments créés par Nervo et données ouvertes](https://github.com/echimine/clone-strava/issues/253); amended: [#219 Segments et Efforts suspects dans le backoffice](https://github.com/echimine/clone-strava/issues/219)

## Links

- **Depends on**: [ADR-017](ADR-017-data-model.md), [ADR-019](ADR-019-activity-creation-flow.md), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-030](ADR-030-itineraries-on-ios.md), [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md), [ADR-038](ADR-038-backoffice-moderation-and-account-deletion.md)
- **Amends**:
  - [ADR-011](ADR-011-backend-worker.md): `segments` queue jobs `match-segment-history`, `replay-segment-medals`, `reconcile-segment-matching`, `export-segments-odbl`.
  - [ADR-017](ADR-017-data-model.md): `best_effort`, `pool_length_m`, the Segment columns, `segment_effort` without `rank` and with several Efforts per Activity, `segment_favorite`, `excluded_source_key`, `activity_matching`.
  - [ADR-019](ADR-019-activity-creation-flow.md): §8 `match-segments` is idempotent and complete, no stored rank, also enqueued after a sport change.
  - [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md): §1 table lists, §2 `segments` depends on `users`, published read views, §5 `segments` jobs, §7 schema contents.
  - [ADR-028](ADR-028-activity-import-from-file.md): FIT pool swims are accepted without positions.
  - [ADR-029](ADR-029-activity-feed-and-card.md): `medalCounts` on the card; the feed reloads the Activity on `activity.segments_matched`.
  - [ADR-030](ADR-030-itineraries-on-ios.md): the Map tab has two modes; « Créer » is a menu; the editor also draws Segments.
  - [ADR-033](ADR-033-activity-detail-edit-delete.md): §5 `reprocess-activity` enqueues `match-segments` after a sport change and skips geocoding when only the analysis lags; §9 replaced by §6, §8 and §13 here.
  - [ADR-035](ADR-035-onboarding-sign-in-code-paywall.md): §6 the Paywall also opens from a Premium lock; `paywall_viewed {entry}`.
  - [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md): §6, §7 analysis v2 with Best efforts; §11 Records, results and medals are no longer out of scope.
  - [ADR-038](ADR-038-backoffice-moderation-and-account-deletion.md): §9 Segment reports; §13 Segments only the athlete has Efforts on are deleted with the account; §16 thresholds for the five real sports and inherited verdicts.
- **Related**: [ADR-010](ADR-010-backend-realtime.md), [ADR-014](ADR-014-revenuecat.md), [ADR-015](ADR-015-posthog.md), [ADR-031](ADR-031-live-recording-on-ios.md), [ADR-032](ADR-032-brand-and-motion-design.md), [ADR-034](ADR-034-activity-engagement-and-live-detail.md)
