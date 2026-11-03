# ADR-036: Athlete profile, follows, and the analysed Activity detail

- **Status**: accepted
- **Date**: 2026-11-03
- **Deciders**: echimine
- **Tags**: profile, social, follows, search, statistics, activities, worker, splits, charts, mobile, ios, api

## Context

Three specs, written from Strava screenshots and the mock-up https://claude.ai/artifact/FVTkepZu2zWD3wATP7QtKb, reshape what an athlete sees of themselves and of others:

- [#136 Profil](https://github.com/echimine/clone-strava/issues/136): the Profile tab becomes an athlete profile (header, Progrès · Activités · Plus, Statistiques, Réglages).
- [#137 Abonnements](https://github.com/echimine/clone-strava/issues/137): follow other athletes, lists, search, another athlete's profile.
- [#138 Carte et détail](https://github.com/echimine/clone-strava/issues/138): sport-dependent card, splits and charts on the detail, kudos and comments on their own screen.

Facts the decisions depend on (code at `bc0532b`):

- `social.follow (follower_id, followee_id, status pending|accepted default 'pending', created_at)` exists, but `FollowUserUseCase` is a stub and no endpoint exists. The feed query and `getVisibleActivity` already honour **accepted** follows (ADR-029 §1, ADR-033 §2).
- Names live in two places: `users.user_profile.first_name/last_name` (written by the Onboarding, ADR-035 §4, and preferred by `AthleteIdentities`) and Better Auth's `user.name`. No endpoint edits either. No user timezone is stored.
- `users.user_sport` (Practiced sports) is written once by the Onboarding and never read back.
- The worker's single computation point is `OfficialValuesService.compute` / `save` (`packages/core/src/activities/services/official-values.ts`), used by `process-activity` and `reprocess-activity`. The stored trace (`trace.json.gz`, schema v2) carries per-point `elevationM`, `heartRateBpm`, `cadenceRpm`. `applyPrivacyZone` trims the route but nothing records that it did. `calories` is never computed.
- A backfill precedent exists: the 10-minute reconciliation sweep enqueues `reprocess-activity` for Activities whose `computed_for_sport_type_code` lags (ADR-033 §5).
- iOS: the Profile tab is a `Form` titled "Compte" (ADR-035 §8); the card always shows Distance · Dénivelé · Temps; the detail shows kudos, comments and a pinned composer inline (ADR-034 §6); Swift Charts is used once (`ElevationProfileChart`).

## Decision

### 1. Follows (amends ADR-017, ADR-021 §6)

- **Statuses** stay `pending` and `accepted`. The API exposes the viewer's relation to an athlete as **`viewerFollowStatus: "none" | "pending" | "accepted"`**, and `null` when the athlete is the viewer.
- **"Approuver mes abonnés"** is stored by `social` in a new table **`social.follow_settings (user_id PK → user cascade, approve_followers boolean not null default false, updated_at)`**. No row means `false`. It is a follow concern, so `social` owns it rather than `user_profile`.
- `follow` gains a `CHECK (follower_id <> followee_id)` and an index `(follower_id, status)` for the "following" list and counts.
- **Endpoints** (all behind `SessionGuard`; an unknown athlete is `404 athlete_not_found`):

| Route | Behaviour |
|---|---|
| `PUT /v1/athletes/:id/follow` | Follow. Creates the row as `accepted`, or `pending` when the athlete approves followers. Idempotent: an existing row is left as is. Self: `422 cannot_follow_self`. Returns `{ athleteId, viewerFollowStatus, followerCount }` |
| `DELETE /v1/athletes/:id/follow` | Unfollow, or cancel a pending request. Idempotent. Same response |
| `GET /v1/athletes/:id/followers` / `following` `?cursor=&limit=` | Accepted follows only, most recent first, keyset on `(created_at desc, user_id)` with an opaque cursor as in ADR-029 §1 (limit 1–50, default 20). Items `{ athlete {id, displayName, avatarUrl}, viewerFollowStatus }`. Any signed-in athlete may read any athlete's lists |
| `GET /v1/me/follow-requests?cursor=&limit=` | Incoming `pending` follows, same shape plus `requestedAt` |
| `PUT /v1/me/follow-requests/:followerId` | Accept (`pending` → `accepted`). `404 follow_request_not_found` if none. `204` |
| `DELETE /v1/me/follow-requests/:followerId` | Refuse: deletes the pending row. Idempotent, `204` |
| `DELETE /v1/me/followers/:followerId` | Remove an accepted follower: deletes the row. Idempotent, `204` |
| `PUT /v1/me/follow-settings` `{ approveFollowers }` | Turning it **on** affects only new follows. Turning it **off** accepts every pending request in the same transaction. Returns `{ approveFollowers }`. `GET /v1/me` gains `approveFollowers` |

- `social` implements the rules (one use case per action); `apps/api` adds identities through `AthleteIdentities`, as for kudos (ADR-034 §1). A batch `SocialService.getFollowStatuses(viewerId, athleteIds)` serves every list that shows a follow button.
- **No domain events and no realtime** for follows: the "X s'est abonné à vous" notification is out of scope. A new followee's Activities appear in the feed at the next refresh.

### 2. Athlete search

- **`GET /v1/athletes/search?q=`**: `q` trimmed, 2–50 characters, otherwise `422 invalid_query`. At most **20** results, no pagination ("refine your search"), the viewer excluded. Items `{ athlete, viewerFollowStatus }`.
- Matching is case- and accent-insensitive **substring** matching on `user_profile.first_name`, `last_name` and `first_name || ' ' || last_name`, using the `unaccent` extension (new migration) and `ILIKE`. It lives in `users` (`UsersService.searchByName`), which owns those columns. Accounts without profile names (only pre-ADR-035 dev accounts) are not findable: accepted. Order: prefix matches first, then alphabetical.
- The app bolds the matched part itself, with the same case- and diacritic-insensitive comparison. No trigram index: the user base is small. Revisit with `pg_trgm` if search gets slow.

### 3. Athlete profile and its Activities

- **`GET /v1/athletes/:id`** (the app passes its own id for its own profile):
  `{ athlete {id, displayName, avatarUrl}, activityCount, streakWeeks, followerCount, followingCount, viewerFollowStatus, followersYouKnow: [identity] (≤ 2), practicedSports: [sportTypeCode], approveFollowers?, pendingFollowRequestCount?, itineraryCount? }`. The last three are only present on one's own profile.
- **What another athlete sees**: every figure on a profile (count, Streak, statistics, Activities list) is computed **only over the Activities that viewer may see** (owner: all `processed`; others: `public`, plus `followers` for accepted followers; never `private`, ADR-033 §2). Nothing about a private Activity leaks through an aggregate.
- **`followersYouKnow`**: up to 2 accepted followers of the athlete whom the viewer follows (accepted), most recent first.
- **`practicedSports`**: the athlete's Practiced sports in their order (`users.user_sport`, read through a new `UsersService.getPracticedSports`), then any other sport of their visible Activities, by number of Activities. An empty list hides the sport chips and selector: Progrès then shows an empty state (no Activity yet) without calling `/v1/me/progress`, and Statistiques shows the all-sports figures.
- **`GET /v1/athletes/:id/activities?cursor=&limit=`**: the athlete's visible `processed` Activities, the **same response as `GET /v1/feed`** (ADR-029 §1, keyset, `FeedAssembler`).
- **Edit the name**: `PATCH /v1/me/profile { firstName, lastName }` (each trimmed, 1–50 characters). It upserts `user_profile` (the name everyone sees) and then sets Better Auth's `user.name` to "Prénom Nom" so the backoffice and emails agree. Both writes are composed in `apps/api` (`users` and `auth` are both layer 0). Returns the profile's `athlete` identity.
- **Composition**: `activities` computes counts, Streak and statistics over its own tables (it may call `social` for the viewer's follow status, ADR-021 §2); `social` gives counts, statuses and `followersYouKnow`; `itineraries` gives `itineraryCount` (new `ItinerariesService.countByOwner`); `apps/api` assembles the response in a new `athletes` module, next to `feed`.

### 4. Weeks, Streak and statistics

- **Weeks** run Monday 00:00 to Sunday 24:00 in **`Europe/Paris`**, a single constant (`ATHLETE_TIME_ZONE`) since no timezone is stored. An Activity belongs to the week of its `started_at`. Athletes abroad see slightly shifted weeks: accepted.
- **Streak**: the number of consecutive weeks, ending with the current week, that each contain at least one visible `processed` Activity. If the current week is still empty, the count ends with the previous week instead, so an empty current week does not break it. The header's Streak covers all sports.
- **`GET /v1/me/progress?sport=`** (own profile only; `sport` required, an active `sport_type`):
  `{ sportTypeCode, weeks: [{ weekStart (date), distanceM, elevationGainM, movingTimeS, activityCount }] × 12, streak { weeks, activeDays: [date] } }`. The 12 weeks run oldest to newest and end with the current week, zero-filled. "Cette semaine" is the last one. `streak.weeks` is the Streak for that sport; `activeDays` are the current month's days with an Activity of that sport.
- **`GET /v1/athletes/:id/stats?sport=`** (`sport` optional; omitted means all sports):
  `{ sportTypeCode | null, recent { weeks: 4, activitiesPerWeek, movingTimeSPerWeek, distanceMPerWeek }, yearToDate { activityCount, movingTimeS, distanceM, elevationGainM }, allTime { activityCount, distanceM, elevationGainM } }`. **ACTIVITÉ** averages the **4 full weeks before the current one** (stable during the week). The year starts on 1 January in `Europe/Paris`. The Plus tab's "Cette année : X km" is `yearToDate.distanceM` without `sport`.
- All aggregates read `activity` + `activity_stats` with SQL `GROUP BY`. No denormalised counters: the volumes are small, and a materialised table would need invalidation on edit, delete and visibility change.

### 5. The activity card (amends ADR-029 §1, §6)

- Feed items (and therefore profile Activities) gain `stats.avgSpeedMs`, **`routeTrimmed: boolean`** and **`recentKudos: [identity]`** (the 3 most recent, newest first).
- **`routeTrimmed`** is a new column `activity_track.route_trimmed boolean not null default false`, set by `compute` when `applyPrivacyZone` removed at least one point. Existing rows get it through the backfill of §7.
- **`recentKudos`** comes from a new batch `EngagementService.getRecentKudoers(activityIds, 3)` (one query, `row_number()` over `kudos_activity_created_at_idx`), added in `FeedAssembler`.
- **Stats by sport** (iOS): a sport whose `paceUnit` is `pace` shows **Distance · Allure · Temps**; `speed` (ride) shows **Distance · Dénivelé · Temps**. Allure comes from `avgSpeedMs`; Temps is the moving time.
- **"Départ et arrivée masqués"**: a small label on the map image when `routeTrimmed`.
- **Social row**: up to 3 overlapping kudos avatars, then "N ont envoyé des kudos · N commentaires" (each part hidden at zero), then the kudos / comment / share buttons. The comment button opens the Kudos and comments screen (§8) on Commentaires with the composer focused.
- The card's author (avatar and name) is tappable and opens the athlete profile (amends ADR-033 §3, ADR-034 §6).

### 6. Activity analysis: splits and series (amends ADR-033 §5, ADR-017)

- During `compute`, the worker derives an **Activity analysis** from the **cleaned trace before the privacy zone** (the same points as the official distance), in a pure `domain/compute-analysis.ts`:
  - **Splits**: one per 1,000 m of distance, counted like `computeMetrics` (legs that straddle a Pause are skipped). Each split is `{ distanceM, movingTimeS, elevationDiffM | null, avgHeartRate | null }`. Its speed is `distanceM / movingTimeS`; `elevationDiffM` is the altitude at its end minus the altitude at its start. The last split covers the rest of the distance if it is at least 10 m.
  - **Series**: at most **300 samples**, evenly spaced along the distance: `{ distanceM: [], speedMs: [], altitudeM: [] | null, heartRateBpm: [] | null }`. Speed is smoothed over a window of about 100 m and is 0 during stops. `altitudeM` is `null` when no point has an elevation, and `heartRateBpm` is `null` when no point has a heart rate.
  - These carry no coordinates, so computing them on the untrimmed trace reveals nothing the privacy zone hides.
- Stored in a new table **`activities.activity_analysis (activity_id PK → activity cascade, version smallint not null, splits jsonb not null, series jsonb null, computed_at)`**, upserted by `save` in the processing transaction, next to `activity_stats` and `activity_track`. A code constant `ACTIVITY_ANALYSIS_VERSION = 1` is written into `version`.
- An Activity without a usable GPS trace (manual entry, sport without GPS, fewer than 2 points) still gets a row with `splits: []` and `series: null`, so the backfill does not pick it again.
- **`GET /v1/activities/:id`** gains `source` (`recorded` | `imported` | `manual`), `importFormat` (`gpx` | `tcx` | `fit`, only for an `imported` Activity whose `activity_import` row is known), `routeTrimmed`, and **`analysis { splits, series } | null`** (`null` while not computed yet). The Allure section's summary rows (moving pace, moving time "Durée de déplacement", pace over elapsed time, elapsed time, fastest split) are derived by the app from `stats` and `splits`. No new endpoint.

### 7. Backfill of processed Activities (amends ADR-033 §5)

- The reconciliation sweep (every 10 min) also selects up to 100 `processed` Activities with **no `activity_analysis` row or a `version` below `ACTIVITY_ANALYSIS_VERSION`**, and enqueues `reprocess-activity` for each with job id **`reprocess-{activityId}-analysis-v{version}`**.
- `ReprocessActivityUseCase` now runs when the sport changed **or** the analysis is missing or outdated; otherwise it is still a no-op. It recomputes everything through `compute` (stats, track with `route_trimmed`, analysis) in one transaction. It emits `activities.activity.updated ["stats"]` only when the sport changed, so the backfill does not flood the owner's realtime topic.
- A backfill job that fails for good keeps its job id, so it is not retried until the next version bump. Accepted, as in ADR-033 §5.
- Raising `ACTIVITY_ANALYSIS_VERSION` later recomputes every Activity, at 100 per sweep.

### 8. Kudos and comments screen (amends ADR-034 §1, §6)

- A pushed screen with a segmented control **Kudos · N** and **Commentaires · N**:
  - Kudos: the paged list of ADR-034 §1, which replaces the kudos sheet.
  - Commentaires: the comments and their **composer pinned to the bottom** of this screen.
  - Optimistic sending, long press (Modifier, Supprimer), live updates on `activity:{id}` and the counts sent back to the feed all stay as ADR-034 decides; only their place changes.
- Opened from the detail's kudos row (Kudos tab), from the detail's comment button and from the card's comment button (Commentaires tab, composer focused).
- Athletes in both lists are tappable and open their profile.

### 9. Activity detail screen (amends ADR-033 §3)

From top to bottom:

1. A toolbar with "⋯" for the author (unchanged).
2. A map about 300 pt tall, with the "Départ et arrivée masqués" label when needed. Tapping it, or its ⤢ button, opens a **full-screen map** (`fullScreenCover`) with Fermer, a button that recentres on the route, and a Distance · Allure · Temps summary (Vitesse for `speed` sports). There is no draggable sheet.
3. The header: avatar and name (tappable), date, place.
4. The title and description.
5. The 2-column stats grid of ADR-033 §3, with the same rule.
6. The source: "Enregistré avec Nervo", "Importé · fichier FIT/GPX/TCX" (only "Importé" when the format is unknown) or "Saisie manuelle".
7. The kudos row (avatars, then "N ont envoyé des kudos"), which opens §8. Then the action bar: kudos, comments with their count, share.
8. **Temps intermédiaires**: Km, Allure (Vitesse for `speed` sports), a bar proportional to speed, Élév., FC. The FC column is hidden when no split has a heart rate.
9. **Allure** (Vitesse): the speed or pace series in `Theme.accent` over the grey altitude area (Swift Charts), then the summary rows.
10. **Fréquence cardiaque**: the curve, then FC moyenne and FC max. Hidden without heart rate.

Sections 8–10 are hidden when `analysis` is `null` or has no splits. Pace charts plot pace with the y axis reversed, so faster is higher.

### 10. iOS structure

- **Colours**: the app's colours only. `Theme.accent` (`#FC5200`, ADR-032) is used for filled buttons, small orange text, routes and charts. The mock-up's darker `#C93F00` is not adopted.
- `Features/Profile` holds the own profile (header, Progrès · Activités · Plus), Statistiques and **Réglages**. Réglages takes over the "Compte" form (ADR-035 §8):
  - Compte: Nom (opens "Modifier le profil") and Email;
  - Confidentialité: "Approuver mes abonnés", Mesure d'audience, Policy and Terms;
  - Se déconnecter, with ADR-030 §8's warning;
  - Debug, in debug builds only.
- The gear opens Réglages and the magnifier opens the search. There is no "+" button.
- **"Partager le profil" is not shown**, on any profile: no public web profile exists.
- A new `Features/Athletes` holds another athlete's profile, the followers and following lists (with the "Demandes d'abonnement" row and swipe to remove a follower), the search and the follow button.
  - The follow button has three states: Suivre, Demande envoyée (tap to cancel), and Abonné ▾ (menu "Se désabonner").
  - Another athlete's profile shows Activités · Plus (their Statistiques), with no Progrès.
- **Navigation**: `AthleteProfileRequest { id }` and `ActivityEngagementRequest { activityId, tab, focusComposer }` live in `Core/Domain`. Every list that shows athletes or Activities receives `openAthlete` / `openActivity` / `openEngagement` closures from the app shell (ADR-007 rule 5). Each tab's `NavigationStack` registers these destinations with one `registerAppDestinations(_:)` (`AppDestinations`, built by the shell), so a profile can be pushed from the feed, a detail, a list or another profile.
- **New `Core` areas** (amends [ADR-007](ADR-007-mobile-architecture.md)): `Core/Domain/Athletes` (models, ports, navigation values), `Core/Athletes` (API adapters, shared paging of an athlete's Activities), `Core/DesignSystem/Athletes` (`AthleteButton`, follow counters) and `Core/DesignSystem/Navigation` (`AppDestinations`).
- The Profile feature does not read the Auth feature's store: the shell passes the signed-in account and the sign-out.
- Realtime topics outside the token are reference-counted on the client (`RealtimeTopicSubscriptions`): the detail and the Kudos and comments screen pushed over it share `activity:{id}`, the first one sends `sub`, the last one `unsub`.
- The 12-week chart and the analysis charts use Swift Charts, in `Core/DesignSystem/Charts` when shared. Tapping a week (`chartXSelection`) shows that week's values.
- Per-user stores (profile, follows) are reset at sign-out like `feedStore`.

### 11. Out of scope

- Avatar upload, the Gallery, Segments, Matériel and Challenges.
- Records, best efforts, results and medals; Mois sportif; the Premium insert.
- Search and filters in the Activities lists.
- Favourites, the "new follower" notification, blocking and reporting, contacts, QR codes and invitations, suggestions.
- Group Activities ("avec X").
- The device name, heart-rate zones, training load, photos, a separate Elevation section, bookmark and replay.
- Calories, which are still never computed.
- A per-athlete timezone.
- Live updates of profiles and lists.

## Alternatives Considered

| Option | Why not |
|---|---|
| Store "approve followers" in `user_profile` | It is a follow rule. `social` would have to read it from `users` on every follow; owning it keeps the rule and its data together |
| Leave pending requests pending when approval is turned off | They would stay stuck behind a setting that no longer asks for approval |
| Count all of another athlete's Activities in their profile figures | Private Activities would leak through counts and totals |
| Denormalised counters and weekly totals | Invalidation on edit, delete, sport and visibility changes for no measurable gain at this size |
| `pg_trgm` index for the search | Unneeded at this size; `unaccent` + `ILIKE` covers accents and substrings |
| Compute splits and series on the phone from a raw-points endpoint | Downloads the whole trace and its exact positions, including what the privacy zone hides; repeated on every device |
| Splits and series columns on `activity_stats` | Large JSON on a row read by every feed page |
| A separate `analyze-activity` job | Would duplicate the reprocessing path; `compute` already reads the trace once |
| Keep comments on the detail | The charts and splits push them far down; Strava moved them to their own screen |
| `#C93F00` for filled buttons (mock-up) | The decider chose to keep the app's single accent colour |

## Consequences

### Positive

- Following finally works, so the feed's follower rules (ADR-029 §1) and the `followers` visibility mean something.
- Splits and series are computed once, server-side, on official points, and old Activities catch up without any manual step.
- One rule ("what the viewer may see") drives the profile, its counts, its statistics and its Activities.

### Negative / Risks

- **`Europe/Paris` weeks** are wrong by a few hours for athletes abroad.
- **The backfill** reads every stored trace from S3 once (100 per 10 min). Watch the worker's load after the deploy.
- **The aggregates** are computed per request. Add an index or a cache if profiles get slow for athletes with thousands of Activities.
- **Search** cannot find accounts without profile names.
- **Two name sources** remain; `PATCH /v1/me/profile` writes both.

## References

- Specs: [#136](https://github.com/echimine/clone-strava/issues/136), [#137](https://github.com/echimine/clone-strava/issues/137), [#138](https://github.com/echimine/clone-strava/issues/138)
- Mock-up: https://claude.ai/artifact/FVTkepZu2zWD3wATP7QtKb
- PostgreSQL `unaccent`: https://www.postgresql.org/docs/current/unaccent.html
- Swift Charts `chartXSelection`: https://developer.apple.com/documentation/swiftui/view/chartxselection(value:)

## Links

- **Depends on**: [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-029](ADR-029-activity-feed-and-card.md), [ADR-033](ADR-033-activity-detail-edit-delete.md), [ADR-034](ADR-034-activity-engagement-and-live-detail.md)
- **Amends**:
  - [ADR-017](ADR-017-data-model.md): `social.follow_settings`, the `follow` check and index, `activity_track.route_trimmed`, `activities.activity_analysis`, `unaccent`.
  - [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md): `social` owns `follow_settings` and `activities` owns `activity_analysis` (§1); the `athletes` composition in `apps/api`, the new batch methods of `social`, `users`, `engagement` and `itineraries`, and the keyset helpers shared in `infrastructure` (§6).
  - [ADR-029](ADR-029-activity-feed-and-card.md): §1 feed item fields, §6 the card.
  - [ADR-033](ADR-033-activity-detail-edit-delete.md): §2 detail fields, §3 detail screen, §5 reprocessing and backfill.
  - [ADR-034](ADR-034-activity-engagement-and-live-detail.md): §1 and §6, the separate Kudos and comments screen and tappable athletes.
  - [ADR-035](ADR-035-onboarding-sign-in-code-paywall.md): §8 "Confidentialité" moves to a Réglages screen.
  - [ADR-007](ADR-007-mobile-architecture.md): the new `Core` areas of §10.
- **Related**: [ADR-030](ADR-030-itineraries-on-ios.md), [ADR-032](ADR-032-brand-and-motion-design.md)
