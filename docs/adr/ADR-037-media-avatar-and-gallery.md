# ADR-037: Media, Avatar and Gallery

- **Status**: accepted
- **Date**: 2026-11-03
- **Deciders**: echimine
- **Tags**: media, photos, videos, avatar, gallery, storage, bucket, upload, offline, mobile, ios, api, worker, analytics

## Context

Athletes want what Strava offers: a photo of themselves, photos and videos on their Activities, a carousel mixing the map and those Media, a full-screen viewer and a Gallery tab on the profile. The decisions were reached on the Wayfinder map [Photos, vidéos et avatar sur iOS (#156)](https://github.com/echimine/clone-strava/issues/156); each section below points to the ticket that holds the detail.

Scope set when the map was charted:

- the existing **OVH Object Storage** assets bucket, through `StorageService`;
- **8 Media at most per Activity**, photos and videos mixed;
- Media are added on the finish screen of a Recording and from the edit sheet (an imported Activity gets its Media through the edit sheet);
- a Media **inherits the visibility of its Activity**, with no visibility of its own;
- everything is free, videos included, with no Premium limit;
- as on Strava, a photo may come before the map.

Facts the decisions depend on (code at `8ff07de`):

- The bucket is private (ADR-009 §6). `StorageService` (`packages/core/src/storage/storage.service.ts`) offers `presignPut` and `presignGet` (15 min by default) and `deleteObject`.
- `activities.activity_attachment (id, activity_id, s3_key, kind photo|video, position, taken_at_point, created_at)` and `users.user_profile.avatar_url` exist but nothing reads or writes them. `AthleteIdentities` falls back to Better Auth's `user.image` (the Google photo).
- `DeleteActivityUseCase` deletes two exact keys after the commit (the trace and the imported file) and only logs a failure.
- The worker image (`node:24-alpine`) has neither ffmpeg nor sharp. The VPS is shared with other apps.
- iOS targets **iOS 17** (`apps/mobile/project.yml`). The profile has three tabs (Progrès, Activités, Plus, ADR-036 §10).
- Verified on the real OVH bucket (2026-11-03): a pre-signed `GET` honours `Range` (`206`, `Accept-Ranges: bytes`), `response-cache-control` and `response-content-type`, and a 7-day URL is accepted. OVH egress is free; there is no bucket policy and no native CDN.
- Strava cuts videos to 30 s, shows 6 Media on mobile and does not charge for videos ([Limites vidéo de Strava et outils média d'iOS](https://github.com/echimine/clone-strava/issues/158)).

## Decision

### 1. Reading from the private bucket ([#157](https://github.com/echimine/clone-strava/issues/157))

- **Everything is read through pre-signed `GET` URLs**, signed by the API in each response. No public read, no API proxy, no CDN: ADR-009 §6 stays intact.
- Access is checked **when the URL is issued**. A URL already issued stays valid until it expires, even if the Activity turns `private`.
- **Lifetimes**: **1 hour** for Activity Media, **7 days** (the SigV4 maximum) for Avatars. The Avatar is public like the name: whoever sees an athlete's name sees their Avatar.
- **Immutable keys**: a new UUID for every upload, and an existing key is never rewritten.
  - `avatars/{userId}/{avatarId}.jpg`
  - `activities/{userId}/{activityId}/media/{mediaId}/{file}` (files in §3)
  - `activities/{userId}/{activityId}/` holds everything that belongs to the Activity, the trace included.
- **The object key never leaves the API.**
- **iOS cache**: `ImageLoader` caches by the URL **without its query string**, which is the immutable object path, not by the full pre-signed URL that changes in every response. Since a path's content never changes, eviction happens only at the cache's size limit. An image missing from the cache that answers `403` (expired URL) makes the screen reload to get fresh URLs.
- `AVPlayer` plays a video straight from its pre-signed URL (Range requests).

### 2. Avatar ([#161](https://github.com/echimine/clone-strava/issues/161), amends ADR-017, ADR-029 §2, ADR-035 §1, §8)

- **One source of truth**: `users.user_profile.avatar_url` becomes **`avatar_key`**. `user.image` is no longer read anywhere; `AthleteIdentities` drops it as a fallback. The identity stays `{ id, displayName, avatarUrl }`, with `avatarUrl` signed from `avatar_key` (7 days) or `null`.
- **Google photo copied once**: when a Google account is created (Better Auth hook), a worker job downloads `user.image`, re-encodes it as a 512×512 JPEG and stores it as the Avatar, **only if the athlete has none yet**. It retries, then gives up (the athlete keeps their initials). Later Google sign-ins never copy anything. A one-off **backfill** does the same for existing accounts. Google's generic letter image is copied as is.
- **Entry points**: a tap on one's own avatar in the profile header, and "Modifier la photo" at the top of `EditProfileSheet`. Both open the same menu: "Prendre une photo", "Choisir dans la photothèque", "Supprimer la photo" (only when there is an Avatar). `PhotosPicker` needs no permission; the camera needs `NSCameraUsageDescription`, and a refusal shows an alert with "Ouvrir Réglages".
- **Crop**: an in-house screen with a circle, drag and pinch zoom.
- **Upload**: the phone produces a **512×512 JPEG** (quality ~0.8, ImageIO, no EXIF or GPS). `POST /v1/me/avatar/upload-url` returns a pre-signed `PUT` to `avatars/{userId}/{avatarId}.jpg` with `Content-Type` and `Content-Length` signed, **1 MB max**. Then **`PUT /v1/me/avatar { avatarId }`** checks the object (`HEAD`) and stores the key. **`DELETE /v1/me/avatar`** removes it. No worker and no variants.
- **Old object**: on replacement or removal, the API deletes the old object right after the database update. A failure is logged; the `bucket-sweep` of §11 catches the orphan. An already issued URL then answers `404` and `AvatarView` shows the initials.
- **While sending**: the new photo shows at once with a spinner; on failure the old Avatar comes back with "La photo n'a pas pu être envoyée". **Network required**: no offline queue (ADR-008 does not apply).
- **"Ajoute une photo de profil"**: a screen after sign-in and before the Paywall, on the Onboarding path only and **only for accounts created by email code** (a Google account already has its photo). Shown once, "Choisir une photo" / "Plus tard", never offered again and not resumed if the app is killed. It cannot be an Onboarding question: those come before the account exists, so nothing could sign the upload.

### 3. Media files, all produced on the iPhone ([#159](https://github.com/echimine/clone-strava/issues/159), amends ADR-011)

- **The server transcodes nothing.** No `media` queue, no worker job per Media, no "processing" state on the server.
- **Photo**: JPEG, 2048 px max, quality 0.8, made by ImageIO (HEIC converted), with no EXIF or GPS. A Live Photo becomes its key still.
- **Video**: MP4 H.264 720p (`AVAssetExportPreset1280x720`) with sound, **1 minute at most**; a longer video is cut to its first minute (`timeRange`) with the note "Vidéo coupée à 1 min". This departs on purpose from Strava's 30 s.
- **Files** in `activities/{userId}/{activityId}/media/{mediaId}/`:

  | Kind | File | Content | Max size |
  |---|---|---|---|
  | photo | `original.jpg` | 2048 px | 8 MB |
  | photo | `thumb.jpg` | 512 px | 1 MB |
  | video | `original.mp4` | 720p, 1 min max | 60 MB |
  | video | `poster.jpg` | 1280 px, first frame | 1 MB |
  | video | `thumb.jpg` | 512 px | 1 MB |

### 4. Upload API ([#159](https://github.com/echimine/clone-strava/issues/159), [#163](https://github.com/echimine/clone-strava/issues/163))

- **`POST /v1/activities/:id/media/upload-urls`** `{ mediaId, kind, files: [{ name, contentType, contentLength }] }` returns a **24-hour pre-signed `PUT`** per file, with `Content-Type` and `Content-Length` signed, so the bucket refuses a heavier file. It writes nothing and may be replayed; it also renews a URL after a `403`. `mediaId` is a UUID made by the phone.
  - Author only (`403`, `404` for an unknown Activity), **whatever the Activity's processing state**.
  - `422` for an inconsistent file set (a video without `poster`, a size above the limit); `409 media_limit_reached` when 8 Media are already confirmed.
- **`POST /v1/activities/:id/media`** `{ id, kind, width, height, durationMs, position }` confirms:
  - for each file, `HEAD` (presence, size), then `GET Range: bytes=0-15` for the signature (`FF D8 FF` for JPEG, a `ftyp` box for MP4); `409 media_missing` or `media_invalid` otherwise; the limit of 8 is checked again;
  - then it inserts the row, **idempotent on `id`**: `201` with the full Media (§7), `200` with the same body on a replay.
  - A row exists only once the Media is ready, so no read filters on a state. Width, height and duration are the phone's (no `ffprobe`); since keys are immutable, a verification job can be added later.
- **`DELETE /v1/activities/:id/media/:mediaId`** answers `204`, also for a Media already gone. It deletes the row, then the Media's folder in the bucket (a failure is logged, §11 catches it). If that Media was first, `media_first` goes back to `false`.
- `StorageService` gains a `contentLength` on `presignPut`, `headObject`, a ranged read, `listKeys(prefix)` and `deleteObjects(keys)`.

### 5. Upload queue on the iPhone ([#159](https://github.com/echimine/clone-strava/issues/159))

- **A GRDB table `media_upload`** (`mediaId`, `activityId`, `kind`, dimensions, duration, `position`, local paths, state `exporting` → `uploading` → `confirming`, plus `failed` with its reason). It is written before sending, and read on wake-up (`handleEventsForBackgroundURLSession`) and at every launch to confirm. The row and its local files are deleted after the `201`. No Media operation goes into `sync_operation`.
- **A background `URLSession`** sends every Media file, cellular data included (`allowsCellularAccess`, not `isDiscretionary`).
- Exports run **one at a time** in selection order; uploads start as soon as an export finishes. An export cut by leaving the app is covered by `beginBackgroundTask`; `BGContinuedProcessingTask` (iOS 26) is not used. If the app is killed during an export, the Media is lost and the athlete adds it again: no copy of the library original is kept.
- **"Enregistrer"** closes the edit sheet at once (as the optimistic edits of ADR-033). New Media appear in **the author's carousel** with their local image and a progress ring; other athletes only see a Media once confirmed. The phone stops the athlete at 8 Media, counting those still being sent.
- **Failures**:

  | Case | Reaction |
  |---|---|
  | `403` from the bucket (URL expired) | `upload-urls` again, then a new upload |
  | 5xx or no network | Backoff, 5 attempts, then "Échec" |
  | `409 media_missing` | Upload again from the local files |
  | `409 media_limit_reached`, `422` | "Échec" at once |
  | `404` (Activity deleted) | Silent abandon, local files deleted |
  | Export impossible | "Échec" |

  A failed tile offers "Réessayer" and "Retirer".

### 6. Media chosen on the finish screen of a Recording ([#160](https://github.com/echimine/clone-strava/issues/160), amends ADR-031 §11, §14)

- The Activity UUID exists from Start (ADR-008 §4), so `activityId` and `mediaId` are known on the finish screen, even offline.
- **The same `media_upload` table**, with a wait condition: a row does not leave while its Activity does not exist on the server (local `recorded`, or `failed` before `create_activity` succeeded). When `ActivitySender` moves the Activity to `created`, the queue coordinator of `App/` (ADR-031 §14) wakes the Media sender, and Media go **in parallel** with `upload_trace` and `complete_activity`.
- **Export starts on selection** on the finish screen, in the app container, while the athlete sets the title and visibility. **Save inserts the `media_upload` rows in the same transaction** as the local Activity and `create_activity` (ADR-031 §11). An unfinished export is saved as `exporting` and continues under `beginBackgroundTask`; a row found `exporting` without its output at relaunch is deleted silently.
- **Finish screen**: the picker is limited to 8 (`selectionLimit`), positions follow selection order. App killed before Save: the selection is lost like the screen's other changes, and the exported files are deleted at relaunch. Resume keeps the selection in memory. Delete wipes everything. An original only on iCloud, picked offline, turns into an error tile "Média indisponible hors connexion" with only "Retirer".
- **`POST /v1/activities`** gains an optional **`mediaFirst`** (default `false`).
- **The Activity does not wait for its Media**: `complete_activity` ignores them, the Activity appears at `processed`, and each Media appears to others once confirmed.
- **Local card** (top of the feed): the author's carousel, with the local static map, then the local images with their progress ring and the failed tiles. At `processed` the local Activity is wiped but active `media_upload` rows stay and keep showing, merged with the confirmed Media.
- **Offline-specific cases** (the rest follows §5):

  | Case | Reaction |
  |---|---|
  | Local Activity `failed` before creation | Media wait; "Réessayer" on the Activity releases them once `created` |
  | Activity `failed` on the server (worker failure) | Media are sent anyway |
  | `404` on `upload-urls` or on the confirmation | Silent abandon, local files deleted |
  | Deleting a local Activity never created | Rows and files deleted at once, `URLSession` tasks cancelled |
  | Deleting through `delete_activity` | Media uploads suspended; rows and files deleted only on `204` or `404`. On `409` (already processing) the Activity goes back to `processing` and its Media resume |
  | Objects sent but never confirmed | Left to the `bucket-sweep` of §11 |
  | Sign-out | The confirmation also counts unsent Media ("2 activités et 3 médias pas encore envoyés seront perdus"), then everything is wiped, background tasks included |

### 7. Reading contract ([#163](https://github.com/echimine/clone-strava/issues/163), amends ADR-029 §1, ADR-033 §2)

- **A Media, everywhere**: `{ id, kind: "photo" | "video", width, height, durationMs, url, posterUrl, thumbUrl }`. A flat object: `durationMs` and `posterUrl` are `null` for a photo. No `position` (the array is ordered), no key and no `expiresAt`. URLs are 1-hour pre-signed `GET`s.
- **Feed items** (so the profile's Activities too) and **`GET /v1/activities/:id`** gain `media: Media[]` (all of them, 8 at most, in order) and `mediaFirst: boolean`. The detail returns `media` whatever the processing state.
- **The app composes the slides**: the map, then the Media; or the first Media, the map, then the rest. `mediaFirst` is ignored when `map` is `null` or there is no Media.
- **Variant per screen** (no new variant):

  | Screen | Photo | Video |
  |---|---|---|
  | Carousel (feed, Activités tab, detail) and viewer | `url` (2048 px, downsampled at decode) | `posterUrl`, then `url` (MP4) |
  | Gallery grid, edit strip | `thumbUrl` | `thumbUrl` |

### 8. Order and "media first" ([#162](https://github.com/echimine/clone-strava/issues/162), [#163](https://github.com/echimine/clone-strava/issues/163), amends ADR-033 §4)

- **As on Strava, the map is always 1st or 2nd.** The state is the order of the Media plus a boolean "media first" (the first Media comes before the map), stored as **`activity.media_first boolean not null default false`**. Without a map, the boolean has no effect.
- **`PATCH /v1/activities/:id`** gains `mediaFirst` and **`mediaOrder: uuid[]`**, the full wanted order, including Media still being sent. The server sets `position = index` for the ids it knows and **ignores unknown ids** (not yet confirmed); a confirmed Media missing from the list goes after the others, in its current order. `422` for duplicates or more than 8 ids; an empty list is accepted. A Media still being sent keeps its index in `media_upload` and sends it as `position` when confirmed, so "Enregistrer" is a single `PATCH`.
- The read order is `(position, created_at)`.

### 9. Gallery ([#163](https://github.com/echimine/clone-strava/issues/163))

- **`GET /v1/athletes/:id/media?cursor=&limit=`** (default 30, max 60, opaque keyset cursor): `{ items, nextCursor }`. Each item is a Media (§7) plus `activity: { id, title, startedAt }`.
- **Order**: the Activity's `startedAt`, newest first, then the Media order within the Activity. `mediaFirst` plays no part.
- **Filter**: only **processed** Activities the viewer may see, with the rule of `GET /v1/athletes/:id/activities` (ADR-036 §3).
- Errors: `404 athlete_not_found`, `422 invalid_cursor`.

### 10. iOS screens ([#162](https://github.com/echimine/clone-strava/issues/162), amends ADR-029 §6, ADR-033 §3, ADR-036 §9, §10)

Prototype (never merged): branch [`prototype/media-carousel-gallery`](https://github.com/echimine/clone-strava/tree/prototype/media-carousel-gallery), commit `0fb2265`.

- **Card carousel** (feed, Activités tab): slides at **86 % of the width**, 4 pt apart, the next one peeking, paging on slides, about 250 pt tall. A single slide (map only or one Media only) is full width, without a carousel. A **video** plays **muted and looped** while it is the current slide, with its duration top right (`0:10`) and a sound button bottom right. Tapping a Media opens the viewer on it; tapping the map or elsewhere on the card opens the detail.
- **Detail header**: the same carousel, edge to edge, about 330 pt. Tapping the map opens `ActivityFullScreenMap`; tapping a Media opens the viewer. The author's "⋯" gains "Ajouter des photos ou vidéos", which opens the edit sheet.
- **Viewer**: black background, one Media at a time (aspect fit), horizontal swipe through the Activity's Media (or the Gallery's). On top: × on the left, "3 sur 8" and the Activity's date in the middle. **Swipe down closes.** A video plays **with sound** when on screen, with native controls, and pauses when another Media comes. **The map is not in the viewer.** From the Gallery only: no "3 sur 8", and a "titre · Voir l'activité ›" pill at the bottom.
- **Gallery tab**: a 4th tab **Galerie** (`photo.on.rectangle`) in the profile: Progrès, Activités, Galerie, Plus; another athlete's profile shows Activités, Galerie, Plus. A **3-column grid of squares**, 2 pt apart, newest first; a video carries "▶︎ 0:10" top right. Tap opens the viewer over all the athlete's Media. Empty: "Aucune photo ni vidéo".
- **Managing Media** (finish screen and "Modifier"): a section "Photos et vidéos" with a **"5/8"** counter and a horizontal strip: the map (a wider tile labelled "Carte") and the Media in carousel order, then an **"Ajouter photos/vidéo"** tile (`PhotosPicker`, images and videos, ordered selection, limited to what remains). At 8/8 the tile is greyed: "Limite de 8 atteinte". Tapping a Media opens "Mettre en premier" / "Supprimer" ("Remettre la carte en premier" on the Media already first). **"Modifier l'ordre"** (from 2 Media) opens a list with handles, Media only.
- **Without a map** (indoor, no GPS): the carousel starts with the first Media; a single Media is full width; no Media keeps the sport icon on a neutral background (`ActivityMapImage`). The edit strip holds only the Media and the "Ajouter" tile, and "Mettre en premier" simply moves the Media to the front.

### 11. Deleting from the bucket ([#164](https://github.com/echimine/clone-strava/issues/164), amends ADR-033 §6, ADR-021 §2 rule 7)

- **Deleting an Activity deletes by prefix**: after the commit, the API lists `activities/{userId}/{activityId}/` (`ListObjectsV2`) and deletes everything with `DeleteObjects` (batches of 1,000), plus the import key `imports/{userId}/{activityId}/source.{format}` outside that prefix. The prefix catches the trace, confirmed Media and files of Media still being sent. It stays **synchronous, in the `DELETE` request**; a failure is logged.
- **`bucket-sweep`**, a daily worker job scheduled like the reconciliation (`upsertJobScheduler`), is the safety net of the whole bucket. It deletes what is older than **7 days** (by the newest object of the folder) and is one of:
  - under `activities/{userId}/{activityId}/` with no `activity` row (missed delete, or a late `PUT` through a 24-hour URL);
  - under `activities/…/media/{mediaId}/` with no `activity_media` row;
  - under `imports/{userId}/{importId}/` with neither an import row nor an Activity;
  - an `avatars/{userId}/{avatarId}.jpg` that is not the user's current `avatar_key`.

  Every "failure logged, orphan tolerated" above becomes an orphan for 7 days at most, plus one pass. If the sweep runs too early on an upload, the confirmation answers `409 media_missing` and the phone sends again from its local copies.
- **Account deletion**: every object of a user lives under `activities/{userId}/`, `imports/{userId}/` or `avatars/{userId}/`, and no user key may be written elsewhere. The future account-deletion job deletes these three prefixes after the database cascade, and the sweep catches its failures. Its trigger, grace period, RevenueCat, PostHog and UI stay with that future work.

### 12. Data model (amends ADR-017, ADR-021 §1)

- `activities.activity_attachment` becomes **`activities.activity_media`**, and the enum `attachment_kind` becomes **`media_kind`** (`CONTEXT.md` bans "Attachment"). New columns `width`, `height`, `duration_ms` (null for a photo); `s3_key` is the key of the Media's folder. `taken_at_point` stays unused.
- New column **`activity.media_first boolean not null default false`**.
- `users.user_profile.avatar_url` becomes **`avatar_key`** (nullable).
- `activities` owns `activity_media`; `users` owns `avatar_key`. `apps/api` signs every URL through `StorageService` when it assembles a response (identities, feed, detail, Gallery).

### 13. Analytics ([#161](https://github.com/echimine/clone-strava/issues/161), [#165](https://github.com/echimine/clone-strava/issues/165), amends ADR-035 §8)

App events only (ADR-015 naming, `enum AnalyticsEvent`), with no image data, place or EXIF, and no `mediaId` or `activityId`. The API sends no Media event: the database counts Media by kind.

| Event | Properties | When |
|---|---|---|
| `activity_media_saved` | `entry: recording\|edit`, `photosAdded`, `videosAdded`, `videosTrimmed`, `mediaRemoved`, `mediaFirst`, `mediaCount` | "Enregistrer" of a session that changed the Media; nothing for an unchanged or abandoned session |
| `media_upload_failed` | `kind`, `reason: network\|limit_reached\|invalid\|export_failed` | Each time a tile turns "Échec" |
| `media_viewer_opened` | `source: feed\|profile_activities\|detail\|gallery`, `kind`, `isOwn` | Viewer opened |
| `gallery_viewed` | `isOwn` | Galerie tab opened |
| `avatar_changed` | `source: camera\|library`, `entry: profile\|edit_profile\|onboarding` | New Avatar stored |
| `avatar_removed` | — | "Supprimer la photo" |
| `avatar_upload_failed` | `reason` | Avatar not sent |
| `avatar_prompt_viewed` / `avatar_prompt_deferred` | — | "Ajoute une photo de profil" shown / "Plus tard" |

The carousel is not tracked; "Réessayer", "Retirer" and the viewer's swipes have no event. ADR-035's first funnel gains `avatar_prompt_viewed` between `signed_in` and `paywall_viewed`.

### 14. Out of scope

- A Premium limit on videos or on the number of Media.
- Media moderation in the backoffice.
- Media on comments; Media captions.
- Photo locations on the map (`taken_at_point` stays unused).
- A profile cover photo.
- Server-side transcoding or verification of the phone's dimensions and duration.
- The rest of account deletion (§11).

## Alternatives Considered

| Option | Why not |
|---|---|
| `public-read` ACL on Avatars | A second read path, an amendment of ADR-009 §6 and an undocumented `x-amz-acl` in a pre-signed `PUT` |
| API proxy for Media | VPS bandwidth, and a bearer header to pass to `AVPlayer` |
| CDN in front of the bucket | Incompatible with pre-signed URLs; egress is already free |
| Server transcoding (ffmpeg + sharp) | About 12–60 s of CPU per video on a shared VPS, libvips with libheif for HEIC, heavier uploads |
| Strava's 30 s video limit | The Strava app accepts more than a minute in practice, despite its help page |
| `upload_media` operations at the end of the Activity's `sync_operation` chain | Media would wait for `complete_activity`, and failure handling would exist twice |
| Blocking Media offline | Contrary to the scope: the finish screen is often offline |
| Waiting for Media before the Activity appears | Delays the Activity by minutes, or forever when a Media fails |
| A free position for the map in the carousel | Strava keeps the map 1st or 2nd; an order plus a boolean is simpler to store and edit |
| A dedicated `PUT …/media/order` endpoint | Two calls on "Enregistrer" |
| A discriminated union for the Media shape | Heavier to decode in Swift |
| A 1024 px variant for the feed | Would reopen the pipeline; the original is downsampled at decode |
| Listing Media from `activity_media` before deleting an Activity | Misses the files of Media still being sent |
| A retried BullMQ job for each bucket delete | A queue and states for no gain over the daily sweep |
| The Avatar prompt as an Onboarding question | The questions come before the account exists, so nothing could sign the upload |
| Keeping `user.image` as the Avatar fallback | Two sources of truth, and Google URLs outside our control |

## Consequences

### Positive

- No new infrastructure: the existing bucket, pre-signed URLs, no CDN, no transcoding worker.
- A Media is either absent or ready: no read filters on a state, and the visibility rule is the Activity's.
- One `media_upload` table serves the online and offline cases.
- The bucket stays clean through one daily sweep, and account deletion has a clear rule for its objects.

### Negative / Risks

- **The server trusts the phone** for dimensions and duration. A modified client could store a wrong size or a long video under 60 MB.
- **A URL already issued** keeps working for up to 1 hour (Media) or 7 days (Avatar) after a visibility change or deletion.
- **An app killed during an export** loses that Media.
- **Large uploads on cellular data**: up to 8 × 60 MB per Activity.
- **The sweep lists the whole bucket daily**: cheap at this volume; revisit when the bucket grows.
- **Two catalogs** (Swift and Zod) to keep up to date, as ADR-015 notes.

## References

- Specs: [#166 Photo de profil](https://github.com/echimine/clone-strava/issues/166), [#167 Photos et vidéos d'une activité](https://github.com/echimine/clone-strava/issues/167), [#168 Carrousel, visionneur et Galerie](https://github.com/echimine/clone-strava/issues/168)
- Map: [Photos, vidéos et avatar sur iOS (#156)](https://github.com/echimine/clone-strava/issues/156) and its tickets [#157](https://github.com/echimine/clone-strava/issues/157)–[#165](https://github.com/echimine/clone-strava/issues/165)
- Research notes: [strava-media-limits.md](https://github.com/echimine/clone-strava/blob/research/strava-media-limits/docs/research/strava-media-limits.md), [media-limits-ios-tools.md](https://github.com/echimine/clone-strava/blob/research/media-limits-ios-tools/docs/research/media-limits-ios-tools.md)
- Prototype: [`prototype/media-carousel-gallery`](https://github.com/echimine/clone-strava/tree/prototype/media-carousel-gallery)
- Strava help, Media: https://support.strava.com/en-us/articles/15401859-adding-videos-and-photos-to-your-activity
- OVHcloud Object Storage limits: https://docs.ovhcloud.com/en/guides/storage-and-backup/object-storage/s3-limitations
- `PhotosPicker`: https://developer.apple.com/documentation/photosui/photospicker
- Background `URLSession`: https://developer.apple.com/documentation/foundation/downloading-files-in-the-background

## Links

- **Depends on**: [ADR-001](ADR-001-global-architecture.md), [ADR-009](ADR-009-backend-api.md) (§6 private bucket), [ADR-018](ADR-018-docker-vps-deployment.md) (assets bucket), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md)
- **Amends**:
  - [ADR-011](ADR-011-backend-worker.md): no `media` queue; the daily `bucket-sweep` and the Google Avatar copy are the worker's only Media-related jobs.
  - [ADR-017](ADR-017-data-model.md): `activity_media` (from `activity_attachment`) with `width`, `height`, `duration_ms`; `media_kind`; `activity.media_first`; `user_profile.avatar_key`.
  - [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md): §1 `activity_media` in `activities`, §2 rule 7 the three user prefixes for account deletion.
  - [ADR-029](ADR-029-activity-feed-and-card.md): §1 `media` and `mediaFirst` on feed items, §2 no `user.image` fallback, §6 the card carousel.
  - [ADR-031](ADR-031-live-recording-on-ios.md): §11 Media on the finish screen, saved in the Save transaction; §14 Media sent once the Activity is created, sign-out count.
  - [ADR-033](ADR-033-activity-detail-edit-delete.md): §2 `media` and `mediaFirst` on the detail, §3 the detail header carousel, §4 `mediaFirst` and `mediaOrder` on `PATCH`, §6 delete by prefix, §10 Media no longer out of scope.
  - [ADR-035](ADR-035-onboarding-sign-in-code-paywall.md): §1 the "Ajoute une photo de profil" screen before the Paywall, §8 Avatar events and the funnel step.
  - [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md): §9 the detail header carousel, §10 the Galerie tab, §11 Avatar upload and the Gallery no longer out of scope.
- **Related**: [ADR-008](ADR-008-mobile-offline-sync.md), [ADR-015](ADR-015-posthog.md), [ADR-019](ADR-019-activity-creation-flow.md), [ADR-028](ADR-028-activity-import-from-file.md)
