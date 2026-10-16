# ADR-031: Live Recording of an Activity on iOS

- **Status**: accepted
- **Date**: 2026-10-15
- **Deciders**: echimine
- **Tags**: recording, mobile, ios, gps, live-activity, itineraries, offline, sync, activities

## Context

The iOS app has to record an Activity end to end. The athlete picks a sport and, optionally, an Itinerary. Live stats depend on the sport, and the distance left on the Itinerary is shown, with a **Return path** worked out when the athlete leaves it with network. The app supports manual and automatic **Pauses**, keeps going in the background with a Live Activity, ends on a minimal finish screen (Save / Delete), and uploads to the server, offline included, until the Activity reaches the feed. Vocabulary is in `CONTEXT.md`: **Recording** ("Enregistrement"), **Pause**, **Return path** ("Chemin recalculé"), **Provisional values**, **Official values**, **Itinerary**.

The decisions were worked out one ticket at a time on the map [Enregistrer une Activity en direct sur iOS](https://github.com/echimine/clone-strava/issues/43). The facts they depend on:

- **Background GPS** ([research](https://github.com/echimine/clone-strava/issues/44)): `CLLocationUpdate.liveUpdates(.fitness)` with a `CLBackgroundActivitySession` is Apple's iOS 17 path. A suspended app is woken; a killed app is relaunched in the background if it rejoins the session within seconds of launch. "When in use" authorization plus the `location` background mode is enough; "Always" adds nothing. Stopping the stream during a stop risks never being relaunched.
- **Device measurements** ([walk only](https://github.com/echimine/clone-strava/issues/56), iPhone 17, iOS 27): background GPS confirmed; Core Location's `stationary` never arrived within 44 s; Core Motion sees a stop in 4-7 s but flips every 1-3 s; 55 % of walking GPS speeds are invalid (`-1`). Running, cycling and battery were **not** measured.
- **Live Activity** ([research](https://github.com/echimine/clone-strava/issues/45), [device test](https://github.com/echimine/clone-strava/issues/54)): available on iOS 17 through a widget extension; local updates have no documented budget; 4 KB of state; 8 h active plus 4 h on the lock screen; `Text(timerInterval:pauseTime:)` freezes in a Pause. On a locked iPhone, a Live Activity button asks for authentication whatever the intent's policy. With "When in use", iOS puts the blue location arrow in the Dynamic Island during a Recording, which pushes the Live Activity to its minimal presentation.
- **Mapbox Directions for the Return path** ([research](https://github.com/echimine/clone-strava/issues/57)): allowed by the Product Terms when triggered by the athlete or by leaving the track, not when polling; 0 to ~6 requests per outing with one Return path per departure from the track. Storing the result breaches §2.10.1, a deviation accepted as in ADR-030 §1 because the app will never be published.
- **Code at `b35c7a2`**: a `Features/Recording` skeleton (GPS stream, provisional distance, GRDB repository left as `TODO`, persistence errors swallowed by `try?`); no `AppDelegate`; trace contract v1 with no notion of Pause; `create`, `upload-url` and `complete` throw `NotImplementedException`; no `GET` or `DELETE /v1/activities/:id`; `GET /v1/me` has no default visibility; `sync_operation` only carries Itinerary changes, with no `BGTaskScheduler`.

## Decision

### Overview

```
Pre-start screen ─ Start ─► Recording (GRDB `recording` row + points + Pauses)
                               │  liveUpdates(.fitness) + CLBackgroundActivitySession
                               │  live stats · Itinerary progress · Return path (Mapbox REST)
                               │  Live Activity (local updates, every 5 s + on events)
                               ▼
                         Finish screen ── Delete ──► nothing left
                               │ Save (one transaction)
                               ▼
              local Activity `recorded` + `create_activity` in `sync_operation`
                               │ ActivitySender: create → upload trace v2 → complete
                               ▼
              `processing` ─► `processed` (GET /v1/activities/:id) ─► local Activity wiped
```

### 1. Recording lifecycle (amends ADR-008 §2)

- A Recording is **not** an Activity state. `recording` leaves the local lifecycle of ADR-008, which now starts at `recorded`: a deleted Recording never becomes an Activity.
- **Phases**: `active`, `paused`, `finishing` (finish screen). Only one Recording exists at a time.
- The Activity UUID is generated at Start (ADR-008 §4) and keys the Recording's points and Pauses.
- **Sports**: `run`, `ride`, `walk`, `hike` (the sports of Itineraries). `swim` and `other` have no GPS and are out of scope. The sport is fixed after Start.

### 2. Starting a Recording

- **Entry points**: the Record tab, and a "Démarrer avec cet Itinéraire" button wherever an Itinerary's detail is shown. The button opens the pre-start screen with the Itinerary chosen, and never starts by itself. While a Recording exists, it reads "Enregistrement en cours" and opens the Record tab, which shows the Recording instead of the pre-start screen.
- **Pre-start screen**: full-screen map on the position (fitting the Itinerary once chosen), a **sport** chip, an **Itinerary** chip ("Aucun" by default, not remembered), the auto-pause switch for a sport that offers it (§4), and a large "Démarrer" button.
- **Sport preselected**: the sport of the last **saved** Recording, kept on the device; `run` the first time.
- **Itinerary list**: every Itinerary in the GRDB cache (ADR-030 §8), newest first. Choosing one switches the sport to its sport; the athlete can change it back. An Itinerary whose track is not cached is listed but not selectable ("Tracé indisponible hors ligne"). An empty list offers "Créer un Itinéraire". An Itinerary deleted elsewhere before Start resets the chip with a toast; after Start, the loaded copy is kept until the end.
- **After Start**: the Itinerary can be **removed** (with confirmation) but never replaced.
- **Location authorization**: "When in use", asked the first time the Record tab opens. Denied or restricted: a message and "Ouvrir Réglages" replace "Démarrer". Approximate location: temporary full accuracy is requested at Start (`requestTemporaryFullAccuracyAuthorization`, `NSLocationTemporaryUsageDescriptionDictionary`); refused, the Recording does not start.
- **GPS indicator**: "Recherche du GPS…", "GPS prêt" (accuracy ≤ 50 m) or "Position approximative". Signal quality never blocks Start.

### 3. GPS in the background

- `liveUpdates(.fitness)` for all four sports, with a `CLBackgroundActivitySession` that lives from Start to Save or Delete. "Always" is never requested.
- **The GPS stream is never stopped during a Pause**: a Pause is a state of the Recording, not of the GPS (automatic resume and Itinerary progress need positions).
- **Relaunch**: an `AppDelegate` (`@UIApplicationDelegateAdaptor`) rejoins the session and restarts the update loop in `didFinishLaunchingWithOptions` when a Recording exists.
- The location stream must surface updates without a position, `isStationary`, speed, course and errors (today dropped), and must not replay a stale position or drop samples silently (`LocationBroadcaster`'s `.bufferingNewest(16)`).
- iOS 17 stays the target: iOS 18's `stationary` proved too slow, and `isStationary` is enough.

### 4. Pauses

- **Manual Pause**: available for every sport. A manual Pause only ends manually.
- **Automatic Pause by sport**: `ride` on by default; `run` offered, off by default; none for `walk` and `hike`. The switch sits on the pre-start screen, is remembered per sport on the device, and can be changed during the Recording in the "…" menu (switching it off during an automatic Pause leaves the Recording paused).
- **Detection** is a pure Swift function over timestamped samples, never a timer. No grace period after Start. After a manual Resume, monitoring continues.
- **Dating**: an automatic Pause starts at detection (no rewind: no written point is erased, the timer never goes back). It ends at the actual departure: the last point within 20 m of the Pause position before the points that move away (or the start of the Core Motion reading that triggered the resume). Points received in between are held in memory, then written; the timer jumps forward.
- **No points is not a stop**: a tunnel or GPS loss never changes the state. Only points showing a stop, or `isStationary`, start a Pause.
- **Cycling (GPS)**: a moving point has a valid speed ≥ 1 m/s; a speed of `-1` is unknown, never stopped. Pause after 10 s without a moving point, with at least one valid speed in the window; if every speed in the window is unknown, movement < 15 m over the 10 s. `isStationary` pauses at once. Resume on a point ≥ 20 m from the Pause position with a valid speed ≥ 1.5 m/s, or ≥ 40 m whatever the speed.
- **Running (smoothed Core Motion)**: "Motion & Fitness" authorization (`NSMotionUsageDescription`) is asked when the athlete turns the switch on; refused, the switch goes back off. `low`-confidence readings are ignored. Pause after 5 s without a `running` reading, with `stationary` at least 4 s out of 5 and no valid GPS speed ≥ 2 m/s in those 5 s; `isStationary` pauses at once; walking never pauses. Resume on a `running` reading or 3 s of continuous `walking`, failing that on the cycling GPS rule.
- **Feedback**: a haptic at the start and end of an automatic Pause, guaranteed in the foreground (`UINotificationFeedbackGenerator`); on the lock screen, `kSystemSoundID_Vibrate` from the background is attempted, with no fallback notification.
- **Validation**: the thresholds are constants of that function, tested by replaying shared timestamped traces (the measured walk must give no Pause). The implementation is accepted only after one ride and one run on an iPhone: today's values come from Strava's 2014 model adapted to the walk measurements.

### 5. Live stats

- **On foot** (`run`, `walk`, `hike`): timer, distance, average pace (min/km). **Cycling**: timer, distance, current speed, average speed (km/h). **No live elevation gain.**
- **Timer** = time since Start minus Pauses; it ticks every second without waiting for the GPS and stops dead during a Pause. Total time is not shown. The gap with the official moving time (the server also drops stretches under 0.5 m/s) is intended.
- **Averages** = distance / timer. Average pace shows "–" for the first 30 s of timer and beyond 59:59 /km.
- **Current speed** = GPS distance over the last ~5 s divided by time (never `CLLocation.speed`); "–" during a Pause, window reset on Resume.
- **Distance**: a pure Swift type applying the server's cleanup rules (accuracy ≤ 50 m, the sport's `maxPlausibleSpeedMs`, nothing across a Pause). The code is not shared with TypeScript, but **shared JSON test traces** run in both the `computeMetrics` / `@repo/geo` tests and the Swift tests: the provisional distance must stay within **±1 %** of the official one.
- **Formats**: metric, French style ("0,00 km", "h:mm:ss", "5:12 /km", "24,3 km/h").

### 6. Following an Itinerary: progress and distance left (offline mode)

- Computed on the phone only, in Swift, from the cached track (`CachedItinerary.track`, resampled every ~20 m). No code shared with `@repo/geo`: the server never needs it.
- The app keeps a **progress**: the distance from the start of the track. Distance left = **total − progress**, never total − Recording distance.
- **Monotonic progress**: each position is projected onto a forward window only (about −30 m to + the distance moved since the previous position + a margin). Progress never goes back; a U-turn on the track freezes the value.
- **First snap**: among track points within **50 m** of the athlete, the first in track order wins (a loop shows the full distance, a start halfway shows what is left from there). Before the first snap, "—".
- **Off the track**: the last value freezes with "Hors Itinéraire". Re-snapping searches the whole rest of the track **ahead** of the progress, so a shortcut lowers the distance left.
- **Finish**: 0 with "Itinéraire terminé"; nothing is triggered.
- Progress follows the real position, during a Pause too, with the live-stats accuracy filter. It is saved with the Recording (§10): re-snapping on resume would send a loop back to its start.
- Tests on synthetic tracks: loop, out-and-back, start = finish, figure eight.

### 7. Return path

- **Trigger**: automatic, no button. The athlete is off the Itinerary when more than **50 m** from the track for **3 accurate points in a row and at least 10 s**; "Hors Itinéraire" shows and the request leaves at the same moment.
- **Destination**: the track point **ahead of the progress** closest to the athlete as the crow flies, never the finish. Distance left = Mapbox distance + (total − progress at the return point). Before the first snap, the Return path leads to the **start** of the Itinerary (distance left = Mapbox distance + total).
- **Display**: dotted line on the map; "Chemin recalculé" replaces "Hors Itinéraire"; distance left follows the athlete's projection on the Return path; the progress bar stays frozen; no haptic, sound or alert.
- **End**: the Return path disappears on re-snapping to the track (§6), on removing the Itinerary or on "Itinéraire terminé", which also cancel any pending request.
- **Leaving the Return path**: more than 50 m from both the Return path and the track for 3 points and 10 s sends a new request with a new return point. The previous Return path stays until the new one arrives. At least **30 s** between two requests, at most **5 requests per departure** (from leaving the track to re-snapping; counter not saved). Beyond that, offline mode until re-snapping.
- **Network**: offline at trigger time, offline mode, retried when the network returns (`NWPathMonitor`) if still off the track. A Return path already shown is kept if the network drops.
- Works during a Pause too.
- **Request**: the Itineraries' REST router (§15) and their dedicated token, 2 points (position, return point), profile `walking` for `run`/`walk`/`hike` and `cycling` for `ride`, `bearings` on the GPS course (± 45°, omitted when invalid; to be added to the router), `radiuses=unlimited`, `steps=false`. `NoRoute` / `NoSegment`: stay "Hors Itinéraire" until the next departure. Temporary failure or `429`: retry after 30 s.
- **Stored** with the Recording (§10), a deviation from Product Terms §2.10.1 accepted as in ADR-030 §1, to be fixed before any release. On resume it is shown without a new request; the leaving rule applies if the athlete is more than 50 m from it and from the track.

### 8. Recording screen

- **Two views and a toggle**: a **stats view** by default (timer at the top, distance very large, sport stats on one line, sport, GPS indicator and "…" menu in the header) and a **map view** (Itinerary track wide and translucent, recorded trace solid, Return path dotted, position, and a compact glass banner with the main stats and the distance left). A round button left of the main button switches at any time.
- The **tab bar is hidden** for the whole Recording.
- **Controls**: one large **Pause** button while moving; **Resume** and **Finish** side by side in a Pause. Finish exists only in a Pause and asks for confirmation, then opens the finish screen.
- **Pause display**: a yellow "EN PAUSE" banner and a tinted background (a chip in the map view), the same for manual and automatic Pauses.
- **Itinerary**: distance left large with a progress bar; the state ("Hors Itinéraire", "Chemin recalculé", "Itinéraire terminé", "—") replaces the "Restant sur l'Itinéraire" label. "Retirer l'Itinéraire" sits in the "…" menu, with confirmation.
- **Write failure banner** (§10): "Impossible d'enregistrer la trace : espace insuffisant" after 30 s of failed writes.

### 9. Live Activity

- **Content**:
  - lock screen: sport icon and name; Time, Distance, and average pace on foot or current speed on a bike; with an Itinerary, a line with the state label, the distance left and a progress bar; a yellow "EN PAUSE" chip in a Pause;
  - compact island: distance (one decimal) and timer, yellow in a Pause. It only shows when the blue location arrow does not take the island, which is accepted;
  - minimal island: sport icon, pause icon in a Pause;
  - expanded island: with an Itinerary, the distance left large (or the state), a start-to-finish bar with the sport icon at the athlete's position (greyed off the track), then timer, distance and pace or speed; without one, the distance large.
- **Timer** = time minus Pauses through `Text(timerInterval:pauseTime:)`.
- **No buttons**: tapping opens the app.
- **Updates**: local, no push; every **5 s**, plus immediately on Pause, Resume, Itinerary state change, Return path arriving, replacing another or disappearing, and Itinerary removal. About 300 bytes of state. *Amended (spec #61 implementation)*: on a 5 s tick, unchanged content is sent again only after **60 s**, just to push the `staleDate` back (the timer runs on its own through `Text(timerInterval:)`); a start refused by iOS is tried again on each tick.
- **Lifetime**: started at Start; a refused or failed Live Activity never blocks the Recording. `staleDate` at 2 min, pushed back on each update; once stale it shows "Enregistrement interrompu", the sport, the distance at the last point and "Ouvre l'app pour reprendre ta Recording.", island in grey. At launch the app ends Live Activities left by a previous run before creating a new one if the Recording resumes. Save: final content ("<sport> enregistrée", duration, distance, pace or speed, "Envoi en cours, elle apparaîtra dans ton flux."), `dismissalPolicy: .default`. Delete: `.immediate`. Beyond 8 h iOS removes it and the Recording goes on.
- **Architecture**: see §15.

### 10. Persistence and resume (GRDB)

- **`recording` table, one row at most**: sport, Itinerary followed (cleared when removed) and its loaded track, `startedAt`, phase, start of the current Pause with its kind (manual or automatic, local only) and position, the auto-pause switch for this Recording, progress and first-snap flag, last Return path and its return point. Updated on each change.
- **Points and finished Pauses** live in separate tables keyed by the Activity UUID.
- **Points**: each raw sample is written **as it arrives**, one transaction per point (~1 Hz, WAL), outside Pauses only, with the trace fields (time, latitude, longitude, altitude, horizontal accuracy, speed). No accuracy filter at write time. A failed write keeps the points in memory and retries them with the next one; the Recording never stops by itself.
- **Not saved**: timer, distance, speeds (recomputed from the points); finish-screen edits (title, visibility), which reopen with defaults.
- **Relaunch by iOS in the background**: resume in the saved phase, no Pause added (the gap counts as a GPS loss). An automatic Pause stays automatic. *Amended (spec #61 implementation)*: any launch in the background counts, not only the one with the `location` launch key (the sync queue's `BGAppRefreshTask` of §14, a `liveUpdates` relaunch without the key); only a launch in the foreground is the athlete opening the app.
- **Opening by the athlete** after a crash or a forced quit: an `active` Recording reopens **paused**, the Pause starting at the last written point, and behaves as a manual Pause. `paused` stays paused; `finishing` reopens the finish screen. No separate "Resume / Finish" prompt.
- **Delete**: one transaction wipes the row, its points and its Pauses. **Sign-out** during a Recording asks for confirmation, then deletes it the same way.

### 11. Finish screen and Save

- Full screen, left only through **Save**, **Resume** or **Delete**.
- **Title** prefilled with the server's formula (`default-title.ts`: "Course à pied le matin / l'après-midi / le soir / de nuit"), computed in Swift at the phone's local time at Start; editable; an empty title falls back to the default on Save.
- **Visibility**: Everyone (`public`), Followers (`followers`), Only me (`private`). Preselected from `defaultVisibility` in `GET /v1/me` (§13), cached; `public` if never loaded.
- **Summary**: mini-map of the trace and the sport's final stats, without a "provisional" label. *Amended by [ADR-032](ADR-032-brand-and-motion-design.md) §5*: for a live GPS Recording of at least 500 m and 2 min, the screen opens with a 10 s celebration (full-screen 3D map drawing the trace, stats counting up, haptics, tap to skip) that ends by shrinking into this mini-map; the rest of this section is unchanged.
- **End**: `endedAt` = **start of the last Pause**; that final Pause is not sent.
- **Too short**: below the sport's `min_duration_s` (60 s, 300 s for `hike`) or with fewer than 2 points, Save is disabled with an explanation. `min_distance_m` is ignored, as on the server. *Amended (2026-10-16, a walk saved standing still)*: `min_duration_s` applies to the **timer** (time in motion, Pauses out), and `min_distance_m` applies too (100 m for `run` and `walk`, 200 m for `ride` and `hike`), on the provisional distance: "Une activité de marche doit faire au moins 100 m pour être enregistrée.". The API refuses the same Activities at creation and the importer the same files ([ADR-019](ADR-019-activity-creation-flow.md) §1, [ADR-028](ADR-028-activity-import-from-file.md) §4).
- **Resume** returns to the Recording in a Pause (the time on the finish screen counts in it). **Delete** asks for confirmation, wipes everything at once and returns to the pre-start screen.
- **Save is one transaction**: insert the local Activity in `recorded` (same UUID, sport, title, visibility, `startedAt`, `endedAt`, provisional values: distance, moving time, total time, **no elevation gain**), add `create_activity` to `sync_operation`, delete the `recording` row (its open final Pause goes with it); points and finished Pauses stay attached to the Activity. Killed before the commit: the finish screen comes back. Then the app switches to the Home tab at the top of the feed, and the Record tab returns to the pre-start screen.

### 12. Trace v2 and server computation (amends ADR-019 §3, §5 and ADR-028)

- `packages/contracts/src/activities/trace.ts`: `schemaVersion: 2`; `points` stays a flat list; new `pauses: [{ startMs, endMs }]`. No kind (manual and automatic look the same). Each Pause lies strictly between two points; no point is written during a Pause; a Recording finished in a Pause does not write that Pause. *Amended (spec #61 implementation)*: a point may sit exactly on a Pause's `startMs` or `endMs` (a Pause starts at a point's time); only a point strictly inside a Pause is refused, and at least one point lies at or before its start and one at or after its end.
- **v2 only**: the v1 schema and its reader are removed (nothing in production, one user). v1 traces already in the bucket can no longer be reprocessed; their computed stats stay. The importer (ADR-028) writes v2 traces without Pauses.
- **`computeMetrics`**: point pairs that straddle a Pause are skipped for **distance** and **moving time** (a train ride during a Pause never counts), and, *amended (spec #61 implementation)*, for **max speed** and **elevation gain** too; **total time** runs from first to last point, Pauses included. The route stays one line, with a straight stroke across a Pause (ADR-029 format unchanged). A Segment effort may contain a Pause and its time includes it.
- The trace is built from the GRDB points and Pauses just before `upload_trace`, never at Save, so it can be rebuilt if lost.

### 13. API (completes ADR-019)

- **Real implementation** of `POST /v1/activities`, `POST /v1/activities/:id/upload-url` and `POST /v1/activities/:id/complete`, as specified in ADR-019 §1, §2, §4.
- **`GET /v1/activities/:id`**, **author only**, whatever the state: summary, official values once `processed`, `processingStatus` and `processingError` (added to the contracts). A non-author gets `404`.
- **`DELETE /v1/activities/:id`**, author only, for `pending` and `failed` Activities: hard delete (ADR-017), `204`. Other states: `409`; unknown or not the author: `404`.
- **`GET /v1/me`** gains `defaultVisibility` (from `user_profile.default_visibility`).
- Contracts, then OpenAPI, then Swift (ADR-026), with response schemas documented (`@ZodResponse`).

### 14. Upload and local Activities (amends ADR-008 §3, §5, §6, §7)

- **Chain**: `create_activity` → `upload_trace` → `complete_activity` in `sync_operation`. Each successful operation is replaced by the next **in the same transaction** as the local state change (`recorded` → `created` → `trace_uploaded` → `processing`), so ordering per Activity holds by construction.
- **`ActivitySender`**, modelled on `ItineraryChangeSender` and reusing `RetryBackoff`. A small **queue coordinator in `App/`** wakes both senders on the shared triggers, so no feature imports another.
- **Trace upload over a regular `URLSession`**, no background session: the whole chain starts right after Save under `beginBackgroundTask`; what is unfinished resumes on the next trigger. A background session would push the upload past the URL's 15 minutes and add a delegate, a file and `handleEventsForBackgroundURLSession` for a trace of a few hundred KB.
- **Triggers**: right after Save, return to the foreground, network back (`ConnectivityMonitor`), feed pull-to-refresh (skipping the backoff delay), and a **`BGAppRefreshTask`** scheduled only while the queue is not empty (`earliestBeginDate` ~15 min), rescheduled while operations remain. It drains Itinerary changes too.
- **Server responses**:

  | Response | Handling |
  |---|---|
  | Offline, timeout, 5xx | Retry from 2 s to 300 s, no attempt limit |
  | 401 | Refresh the session, then retry |
  | 403 from the bucket (URL expired) | `upload-url`, then upload again |
  | `200` without URL on `POST` (already `processing`) | Straight to `processing` |
  | 409 on `upload-url` (no longer `pending`) | Go to `complete` |
  | 409 `trace_missing` on `complete` | Back to `upload_trace` with a new URL |
  | 422; 409 on `POST` (another athlete's UUID); 409 `trace_too_large`; 409 on `complete` of an Activity `failed` on the server | `failed` locally, with the message |

- **Tracking**: the app calls `GET /v1/activities/:id` for each local Activity in `processing` on return to the foreground, on each WebSocket reconnection, and on `activity.processed` or `activity.failed` (now listened to).
- **At `processed`**: reload the first feed page, then wipe the local Activity (row, points, Pauses) once the reload succeeds, or at the latest on the next refresh that contains its UUID. No simplified route is kept locally: the feed has no local cache. **At `failed`**: the local Activity goes `failed` and keeps its points.
- **Feed**: local Activities not yet processed are always **on top**, newest first; a local card whose UUID is already in the server response is dropped. A local card shows title, sport, date, distance and moving time (provisional values), a Mapbox Static image from the local points (polyline5 simplified to 2,000 characters on the phone, no privacy zone since only the author sees it), no elevation gain, place, kudos, comments or share, and a status line: "En attente de réseau", "Envoi…", "Nouvel essai bientôt", "Traitement…", "Échec de l'envoi" with the reason.
- **Delete** (with confirmation) on any local Activity not yet `processing`, and on `failed`. If `create_activity` succeeded, a **`delete_activity`** operation calls `DELETE /v1/activities/:id` and cancels the Activity's pending operations; otherwise the delete is local only. *Amended (spec #61 implementation)*: the card goes at once, but the local copy of an Activity the server may have stays, hidden, until the server answers: wiped on `204` or `404`; on `409` (already handed to the worker) it comes back in `processing`, followed like any other, and the feed says "Suppression impossible : l'activité est déjà en traitement.".
- **Retry**: only after an API refusal (a worker failure is retried from the backoffice). The Activity returns to the state before the failure and resumes at the refused step.
- **Sign-out**: one confirmation counts the Activities not yet sent (`recorded`, `created`, `trace_uploaded`, `failed`: "2 activités pas encore envoyées seront perdues"), and also covers the Recording in progress and pending Itinerary changes; then everything is wiped locally. An Activity in `processing` is safe on the server.

### 15. Where the code lives (amends ADR-007)

- **`Core/LocalActivities/`**: the local Activity, its points and Pauses (GRDB tables and migrations), its repository with the Save transaction and the state transitions, the trace v2 builder, and `ActivitySender`. Recording writes through it, the Feed reads it, the queue coordinator in `App/` drives it. Shared types join `Core/Domain/Activities/`.
- **`Core/Routing/`**: `MapboxDirectionsRouter`, `RoutingProfile` and `RetryBackoff`, moved out of `Features/Itineraries` (with `bearings` added). Itineraries and Recording both use them.
- **Itinerary read side**: a protocol in `Core/Domain` lists cached Itineraries and loads a track; `GRDBItineraryCache` implements it. Itineraries keeps writing the cache.
- **`Features/Recording`**: Recording domain (phases, Pause detection, live stats, Itinerary progress, Return path rules) as pure Swift; `RecordingService` actor; GRDB `recording` repository; Core Motion adapter; screens. "Démarrer avec cet Itinéraire" reaches it through a navigation closure from the app shell, never by import.
- **Live Activity**: a widget extension target (`app-extension`, `com.apple.widgetkit-extension`) in `project.yml`, with `NSSupportsLiveActivities = YES` in the app. The `ActivityAttributes` type (plain values only, ActivityKit) sits in a folder compiled into both targets, outside `Features/`. Recording's domain sees a `RecordingLiveActivity` port; its ActivityKit adapter lives in `Features/Recording/Infrastructure`.
- **`App/`**: the `AppDelegate` for relaunch (§3), the queue coordinator and the `BGAppRefreshTask` registration (§14).
- **Info.plist**: `NSMotionUsageDescription`, `NSLocationTemporaryUsageDescriptionDictionary`, `NSSupportsLiveActivities`, `BGTaskSchedulerPermittedIdentifiers` and the `fetch` background mode.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| `startUpdatingLocation` with `allowsBackgroundLocationUpdates` | Everything stops once the app is killed; no relaunch |
| Ask for "Always" to keep the Dynamic Island compact | Adds nothing to continuous tracking; the blue arrow is accepted instead |
| Stop the GPS during a Pause | Breaks automatic resume and Itinerary progress, and a killed app is never relaunched |
| Trace v2 in segments, or pause markers between points | Every reader (cleanup, route, Segments) would change; intervals keep `points` flat |
| Keep a v1 reader next to v2 | Nothing in production, one user: dead code |
| Automatic Pause on GPS speed for every sport | 55 % invalid speeds when walking; false Pauses measured |
| iOS 18 target for `stationary` | Too slow on device (> 44 s) |
| Distance left = total − Recording distance | Drifts with any shortcut, detour or mid-track start |
| Return path to the finish | A loop would send the athlete straight back to the start |
| Return path on a button, or periodic polling | A button means a fiddly action on the move; polling looks like the automated queries §1.9 forbids |
| Live Activity buttons | Authentication asked on a locked iPhone; Strava offers none either |
| Background `URLSession` for the trace | Upload delayed past the 15-minute URL validity, plus delegate and file plumbing for a small file |
| `recording` kept as an Activity state | A deleted Recording would have been an Activity; contradicts the glossary |
| Local Activities in `Features/Recording`, bridged to the Feed in `App/` | The Feed and the coordinator would reach into a feature through adapters; shared code moves to `Core/` (ADR-007 rule 5, as in ADR-027) |
| Recording declares its own Itinerary and router ports, wired in `App/` | Two ports for code that is already shared; the router moves to `Core/` instead |

## Consequences

### Positive

- No Activity is lost: every point is on disk within a second, the app resumes after being killed, and the upload resumes at the right step.
- The phone and the server compute distance the same way, checked by shared test traces.
- A Pause means the same thing everywhere: timer, trace, server metrics, Live Activity.
- The Itinerary keeps working offline; the Return path only adds to it when the network is there.
- The feed shows a just-saved Activity at once, then swaps it for the official one.

### Negative / Risks

- **Auto-pause thresholds unvalidated**: running and cycling were never measured on a device; the implementation issue must close only after real outings.
- **Battery not measured.**
- **Live Activity mostly minimal** in the Dynamic Island because of the blue arrow.
- **Mapbox terms**: storing the Return path breaches §2.10.1, like ADR-030; the shared free tier of 100,000 requests/month now covers editing and Recording.
- **v1 traces** in the bucket can no longer be reprocessed.
- **`BGAppRefreshTask`** timing is not guaranteed; uploads still mostly happen on Save and when the app opens.
- **Lock-screen haptic** for automatic Pauses is not guaranteed by any Apple source.
- **More code in `Core/`**: local Activities and routing move up, which widens what every feature can see.

## References

- Research: [Background GPS and automatic Pause](https://github.com/echimine/clone-strava/blob/research/recording-background-gps-autopause/docs/research/recording-background-gps-autopause.md), [Live Activity](https://github.com/echimine/clone-strava/blob/research/recording-live-activity/docs/research/recording-live-activity.md), [Return path with Mapbox Directions](https://github.com/echimine/clone-strava/blob/research/recording-reroute-mapbox-directions/docs/research/recording-reroute-mapbox-directions.md)
- Prototypes (throwaway branches): `prototype/recording-screen`, `prototype/recording-live-activity`; test benches: `task/live-activity-lock-test`, `task/recording-autopause-battery`
- Map and decision tickets: [Enregistrer une Activity en direct sur iOS](https://github.com/echimine/clone-strava/issues/43)
- `CLLocationUpdate`: https://developer.apple.com/documentation/corelocation/cllocationupdate
- `CLBackgroundActivitySession`: https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession
- ActivityKit: https://developer.apple.com/documentation/activitykit
- `BGAppRefreshTask`: https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask
- Mapbox Directions API: https://docs.mapbox.com/api/navigation/directions/

## Links

- **Amends**: [ADR-007](ADR-007-mobile-architecture.md) (`Core/LocalActivities`, `Core/Routing`, widget extension), [ADR-008](ADR-008-mobile-offline-sync.md) (§2 no `recording` state, §3 no background `URLSession` and `BGAppRefreshTask`, §5 response table, §6 no provisional elevation gain, §7 local Activity wiped at `processed`), [ADR-019](ADR-019-activity-creation-flow.md) (§3 trace v2 and regular `URLSession`, §5 metrics across Pauses, new `GET` and `DELETE /v1/activities/:id`), [ADR-028](ADR-028-activity-import-from-file.md) (the importer writes v2 traces)
- **Amended by**: [ADR-032](ADR-032-brand-and-motion-design.md) (§11 the finish screen opens with the celebration)
- **Related**: [ADR-006](ADR-006-mobile-stack.md), [ADR-017](ADR-017-data-model.md), [ADR-025](ADR-025-mobile-testing-strategy.md), [ADR-026](ADR-026-openapi-swift-codegen.md), [ADR-027](ADR-027-user-location-on-maps.md), [ADR-029](ADR-029-activity-feed-and-card.md), [ADR-030](ADR-030-itineraries-on-ios.md)
