# ADR-038: Backoffice, moderation and account deletion

- **Status**: accepted
- **Date**: 2026-11-04
- **Deciders**: echimine
- **Tags**: backoffice, admin, moderation, report, block, ban, sanction, audit, account-deletion, jobs, bullmq, premium, revenuecat, posthog, email, segments, ios, api, worker

## Context

The backoffice (`apps/admin`, ADR-004, ADR-013) can sign an Administrator in with password + 2FA (ADR-022 §5, ADR-035 §3), but almost nothing behind it works: the Users, Segments and Dashboard pages are empty, the Activities list and detail are shells with no API behind them, and the only admin endpoint is `POST /v1/admin/activity-imports/:id/reprocess`. Athletes cannot report content, block each other or delete their account.

The decisions were reached on the Wayfinder map [Backoffice Nervo (#190)](https://github.com/echimine/clone-strava/issues/190); each section below points to the ticket that holds the detail.

Scope set when the map was charted:

- **no v1**: every module below ships together;
- **a single `admin` role** that may do everything, with no sub-roles;
- **every admin action is recorded** in an audit log, and a Sanction always carries a reason;
- **Report** from the iOS app on a comment, an Activity (with its Media) or an athlete; Media are moderated through their Activity;
- **one account deletion service**, called by the backoffice and by a "Supprimer mon compte" button in the app;
- **Segments are created by athletes in the app**, on another map; the backoffice only reviews Suspicious efforts and renames or deletes a Segment;
- **the app will never be published** (decided 2026-11-04): App Store rules motivate nothing any more. Report, Block and "Supprimer mon compte" stay as product features; there is no 24-hour obligation (the age badge stays), no EULA, no text filter, no public legal page.

Facts the decisions depend on (code at `cd31835`):

- `better-auth@1.7.6` with the `admin` plugin. `banUser` sets `banned`, `banReason`, `banExpires` and deletes every session. Sessions live only in Redis and the iOS bearer is the session token, so the cut is immediate. A ban is checked only when a session is created; every sign-in path then answers `403 { code: "BANNED_USER" }`. `listUsers` searches one field, case-sensitively. The plugin's routes under `/api/auth/admin/*` check the role only, not the strong session. Research: [better-auth-admin-plugin.md](https://github.com/echimine/clone-strava/blob/research/better-auth-admin-plugin/docs/research/better-auth-admin-plugin.md).
- `user.role`, `banned`, `ban_reason`, `ban_expires` and `session.impersonated_by` exist and are unused.
- `ProcessActivityUseCase` returns early when the Activity is not `processing`: a raw BullMQ retry does not reprocess a `failed` Activity. Completed jobs are kept 24 h and failed jobs 7 days (`DEFAULT_JOB_RETRY`); the two schedulers' jobs and `match-segments` are never removed. Research: [bullmq-admin-queues.md](https://github.com/echimine/clone-strava/blob/research/bullmq-admin-queues/docs/research/bullmq-admin-queues.md).
- The RevenueCat SDK is not wired, so no RevenueCat customer exists yet; `SyncSubscriptionUseCase` throws `NotImplementedException`. `POSTHOG_API_KEY` is a project key that cannot delete. Research: [revenuecat-posthog-account.md](https://github.com/echimine/clone-strava/blob/research/revenuecat-posthog-account/docs/research/revenuecat-posthog-account.md).
- `segments.segment` has no creator column and no API; `match-segments` is a stub that fails on every processed Activity.
- `NotificationsService.sendAuthEmail` is the only sender, from `noreply@mail.strava.echimine.fr`, with four React Email templates.

## Decision

### 1. Shape of the admin API

- Admin endpoints stay in `apps/api` under `/v1/admin/*`, behind `SessionGuard` + `AdminGuard` (strong session), and call the services of the modules (ADR-021 §1, "admin is not a module").
- **Each action on a piece of content is one domain action with one endpoint**, shared by every screen that offers it (Activities screen, moderation queue, user sheet). The moderation queue has no actions of its own beyond closing a case.
- Ban, unban, sign-out, role and account removal go through **`auth.api.*`** (`banUser`, `unbanUser`, `revokeUserSessions`, `setRole`, `removeUser`) with the request headers, never through a direct write: the plugin keeps its own guards and revokes the sessions. Its `APIError`s are translated to our error format.
- The plugin's own HTTP routes (`/api/auth/admin/*`) **stay exposed**: they check the role only, which bypasses the strong session. Risk accepted: no Administrator signs in to the iOS app. `impersonate` is not used (§19).
- Request and response schemas live in `packages/contracts` (`admin` namespace), as for every exchange (ADR-013 rule 5).

### 2. Admin list conventions (amends ADR-013 "Tables and filters")

Decided here, without a ticket, when the fog was cleared:

- **Offset pagination with a total**: `?page=1&pageSize=50` (25, 50 or 100), response `{ items, total, page, pageSize }`. Admin tables show page numbers; the keyset helpers of ADR-036 stay for the app's infinite lists.
- **One search box** `q` per list, case- and accent-insensitive (`unaccent` + `ILIKE`), over the fields each list names.
- **Sort** through `sort=<field>` and `order=asc|desc`, from a whitelist per list; every list has a default sort.
- **Filters** are plain query parameters; periods are `from`/`to` dates. Days are cut in Europe/Paris time.
- Every list's state is in the URL (ADR-013), and a list a link opens (for example "Voir ses Activités" from a user sheet) is just a pre-filled URL.

### 3. Audit log ([#195](https://github.com/echimine/clone-strava/issues/195), amends ADR-021 §1, §2)

- New domain module **`audit`**, layer 0, owning `audit.admin_audit_entry`.
- **Scope**: every successful write under `/v1/admin/*`, plus an Administrator's 2FA changes and any grant or removal of the `admin` role. No reads, no sign-ins, no refused attempts.
- **Declarative writing**: an `@Audited("<action>")` decorator on each admin route and an interceptor that writes **after success** (target from the route parameters, reason from the body). A test fails when a non-`GET` admin route is not decorated. There is no shared transaction with the action: a failure to write the entry is logged as an error. Better Auth hooks (2FA, role) call the same service.
- **An entry**: author (optional, shown "Système"), action (dotted name from a closed list, §17), target type and id, **subject athlete** `subjectUserId` (optional: the author of a removed comment, for example), reason, `details` JSON limited to the action's parameters (Ban duration, Premium duration, counts and ids of a batch), `requestId`, date. No IP, no user agent, **never a copy of content**.
- **No foreign key**, no snapshot of a name or an e-mail: an entry survives account deletion and then shows "Compte supprimé". Kept forever, append-only on the application side (no update or delete endpoint).
- **Screens**: a global "Journal" filterable by author, action, subject athlete and period (`GET /v1/admin/audit-entries`), and a "Historique" section on the user sheet (entries whose subject athlete they are).
- A first Administrator promoted in SQL on the VPS is not recorded: accepted gap.

### 4. Sanctions, reasons and e-mails to the athlete ([#195](https://github.com/echimine/clone-strava/issues/195), [#208](https://github.com/echimine/clone-strava/issues/208), amends ADR-023)

- A **Sanction** (glossary) is an action that takes something away from an athlete, restricts them or deletes something of theirs: Ban and unban, sign-out everywhere, removing a comment, an Activity or a Media, resetting an Activity's title and description, resetting a name, bio or Avatar, renaming or deleting a Segment, deleting an account.
- **A Sanction requires a non-empty free-text reason**, and the athlete reads it: every Sanction dialog says so. Other admin actions take an optional reason, except granting or removing Promotional Premium (§12), which requires one.
- **Every Sanction except sign-out sends one e-mail** to the athlete concerned: what was sanctioned, named without a link ("votre Activité « Sortie du dimanche » du 2 novembre"; a comment is quoted, truncated to about 200 characters), the reason as typed, a Ban's end date or "définitivement", and the contact address. One e-mail per Sanction, never grouped.
- **No e-mail** when a temporary Ban ends by itself, when a Suspicious effort is rejected (not a Sanction), when a case is dismissed, or to a Segment that has no creator any more. A banned athlete who is sanctioned again still gets the e-mail.
- **The e-mail never mentions a Report**, nor who sent it: the author learns about the Sanction, never about the Report.
- **Contact address**: one team address, configured by `CONTACT_EMAIL` and forwarded to the Administrators. It is the `Reply-To` of every e-mail to an athlete and is shown on "Compte suspendu". Contesting means replying.
- **Sending**: transactional, in French, without an unsubscribe link, **after success, through a job** in a new `emails` queue, with the audit entry id as idempotency key. The data the e-mail needs (address, first name, quoted text) is put in the job, since the content or the account may be gone. `NotificationsService.sendAuthEmail` becomes a general `sendEmail` with an optional `replyTo`; one React Email template per family (Ban, unban, content removed, profile reset, Segment, account deleted, new report case for the Administrators).

### 5. Users: list and sheet ([#200](https://github.com/echimine/clone-strava/issues/200))

- **List** (`GET /v1/admin/users`): search over first name, last name and e-mail (our own query in a repository, not `listUsers`); filters role, state (active, banned, temporarily banned), Premium (§12), sign-in method (e-mail code, Google), sign-up period; columns Avatar + name, e-mail, sign-up, sign-in methods, Activity count, last Activity, Premium, state ("Banni jusqu'au …"); sort by sign-up (default) or last Activity.
- **Sheet** (`GET /v1/admin/users/:id`) in eight sections: header (Avatar, name, e-mail, Admin/Banni/Premium badges, sign-up, actions); Account (sign-in methods, 2FA for Administrators, open sessions with device, opening and expiry, from `GET …/sessions`); Athlete profile (bio, city, country, sports, Level, default visibility — **never birth date, gender or weight**); Activity (counts, last Activity, Streak, link to the filtered Activities list); Follows (counters, plus "Bloqué par N athlètes", §8); Premium (§12); Reports (tabs "reçus" and "émis"); Historique (§3).
- **Ban**: closed choice **24 h / 7 j / 30 j / définitif**, required reason, confirmation that repeats the end date. Banning again replaces the duration; there is no "edit duration". **Unban** is a Sanction with immediate effect. If the athlete is a paying Premium subscriber, the dialog warns that Apple keeps billing.
- **"Déconnecter partout"**: a separate Sanction (`revokeUserSessions`); the athlete can sign in again at once. No per-session sign-out.
- **Resets**: three separate Sanctions without free input: bio emptied; Avatar removed (object deleted, initials shown); name replaced by first name "Athlète" and an empty last name. The athlete can change everything again.
- **Admin role** from the backoffice (`PUT …/role`): an Administrator cannot demote themselves nor the last Administrator; a promoted account sets up 2FA at its first backoffice sign-in; **an Administrator can be neither banned nor deleted** without being demoted first; optional reason (not a Sanction); strong confirmation by typing the e-mail again.

### 6. Effects of a Ban ([#200](https://github.com/echimine/clone-strava/issues/200), amends ADR-022 §3)

- A Ban is **active** when `banned and (ban_expires is null or ban_expires > now())`: a Ban whose end has passed counts as over even if the row keeps `banned = true` until the next sign-in.
- **Hidden at read time**, nothing deleted or changed: profile `404` ("Ce profil n'est plus disponible"), Activities out of the feed, profiles and Gallery, comments hidden, Efforts out of leaderboards, absent from follower, following and kudos lists, pending Follow requests hidden. **Counters unchanged.** Segments they created stay. Everything comes back at the end date without waiting for a sign-in.
- **iOS**: the next request gets a `401` and the app signs out as for an expired session. At the next sign-in it recognizes `403 BANNED_USER` and shows **"Compte suspendu"**: end date or "définitivement", the reason, and the contact address. `bannedUserMessage` (a function) puts the end date and reason in the response. Sending a Sign-in code to a banned athlete is accepted; only its validation fails.
- A banned athlete stays counted in statistics.

### 7. The viewer filter (decided here)

Ban (§6), Reports (§9) and Blocks (§8) all hide things at read time. They are applied in one place:

- `apps/api` builds, per request, a **viewer filter**: athletes hidden from the viewer (actively banned, plus blocked in either direction) and items the viewer reported (comment and Activity ids). It costs one query per owning module: `auth` (active Bans), `social` (Blocks) and `moderation` (reported items).
- Read methods of `activities`, `engagement`, `social` and `users` take that filter as an **exclusion parameter**, in the same way `apps/api` already composes the feed (ADR-029) and the athlete pages (ADR-036). No module gains a dependency on another for this.
- Leaderboards apply the same filter when the Segments-in-app map builds them.

### 8. Block an athlete ([#206](https://github.com/echimine/clone-strava/issues/206), amends ADR-021 §1, ADR-036)

- **Two-way**: when A blocks B, each sees the other as nonexistent: profile `404` (same as a Ban), absent from search, feed, follower, following and kudos lists, Activities and Media not found even when public, Gallery closed, Efforts hidden from leaderboards. No notice to anyone.
- **Follows and Follow requests are deleted** in both directions, in the same transaction; no new Follow while the Block lasts; nothing comes back on unblock.
- **Comments and kudos** already exchanged are **hidden at read time** in both directions, under third parties' Activities too; counters unchanged; they come back on unblock.
- **iOS**: "Bloquer" in the "…" menu of an athlete's profile, and "Bloquer aussi <prénom>" in the confirmation of any Report. The confirmation sheet explains the effects. Settings get an "Athlètes bloqués" list with a confirmed "Débloquer"; each athlete sees only those they blocked. Online only.
- **API**: `PUT /v1/me/blocks/:athleteId` (idempotent), `DELETE /v1/me/blocks/:athleteId`, `GET /v1/me/blocks`. No self-block; no limit.
- **Model**: module `social`, table `social.athlete_block (blocker_id, blocked_id, created_at)`, unique on the pair, both foreign keys `on delete cascade`. Blocks survive a Ban.
- **Backoffice**: only the "Bloqué par N athlètes" counter on the user sheet; not in the audit log; an Administrator can be blocked like anyone.
- PostHog: `athlete_blocked` and `athlete_unblocked` with `source` (`profile` | `report_confirmation`), without the blocked athlete's id.

### 9. Report from the iOS app ([#199](https://github.com/echimine/clone-strava/issues/199), amends ADR-021 §1, §2)

- **Entry points**: "Signaler" in the long-press menu of other athletes' comments; in the "…" menu of an Activity's detail (now shown on other athletes' Activities) and the long-press menu of a feed card; in a new "…" menu on an athlete's profile. Never on one's own content (hidden, `422`).
- **Reasons**: "Spam ou publicité", "Harcèlement ou propos haineux", "Contenu sexuel ou violent", "Usurpation d'identité" (athlete only), "Autre". Optional note (500 characters at most), **required with "Autre"**. An Activity is reported as a whole.
- **After sending**: "Merci, notre équipe va examiner ce signalement", plus the Block proposal (§8). A reported comment or Activity is **hidden for the reporter**, on all their devices, **for good**, whatever the outcome (via the viewer filter, §7; a detail opened by a link answers `404`). A reported athlete is never hidden by the Report itself.
- **Rules**: one Report per reporter per open case; a repeat answers `200` "Déjà signalé". At most **20 Reports per 24 h** per athlete (`429`). Online only.
- **Copy**: the Report keeps a copy of the texts at sending time (comment text; Activity title and description; athlete name and bio), and only a reference for Media and Avatar. The copy is erased when the case closes or when the author's account is deleted. The reporter's note is kept.
- **API**: `POST /v1/reports { targetType, targetId, reason, note? }` → `201`, `200` (already reported), `404` (target missing or invisible), `422` (own content, missing note), `429`.
- **Module**: `moderation`, layer 0. The `apps/api` handler reads the target through its module (existence, visibility for the reporter, author, texts to copy) and calls `moderation.report(...)`.
- PostHog: `report_submitted { target_type, reason }`, emitted by the API after commit, without target id or text; nothing on a `200`.

### 10. Moderation queue ([#201](https://github.com/echimine/clone-strava/issues/201))

- **One case per target**: Reports stay individual, but the queue shows one item per target, stored in `moderation.report_case`. A target has at most one open case; the first Report opens it, the next ones join it (`report.case_id`); after closing, a new Report opens a new case.
- **Closing is explicit**: the Administrator applies zero or more Sanctions from the case, then "Clore" with **"Sanctionné"** or **"Rejeter"**; every Report of the case closes together. "Sanctionné" requires at least one Sanction recorded since `opened_at` on the target **or on its author** (a Ban of the author is enough). Closing is recorded (`report.resolve` / `report.dismiss`) with an optional note; it is not a Sanction. A case already closed answers `409`, as does `resolve` without a Sanction.
- **Automatic close when the target disappears**, whatever the path (Sanction, deletion by the author, author's account deleted): `moderation` listens to deletion events. Outcome "Sanctionné" if the deletion was a Sanction, "Cible supprimée" otherwise, author "Système".
- **No automation, no notice**: no hiding above a threshold; the reporter never learns the outcome; the author learns only of a Sanction (§4).
- **E-mail to every Administrator** when a case opens (not on later Reports): target type, reason and link, no copy of content; through the `emails` queue.
- **List** (`GET /v1/admin/reports?state=open|closed`): tabs "À traiter" and "Clos"; oldest open case first with a **red badge past 24 h**, then by Report count; filters target type, reason, opening period; columns type, preview (copy from the first Report, truncated; Avatar thumbnail for an athlete), author, Report count, reasons, age.
- **Detail** (`GET /v1/admin/reports/:caseId`): current content, with each Report's copy beside it marked "modifié depuis le signalement" when it differs; the Reports (reporter with a link, or "Compte supprimé"; reason, note, date); the author (link, Banned badge, Reports received and past Sanctions from the audit log). A closed case shows outcome, who closed it and when, the note, and the Reports without their copy.
- **Actions by target**, each calling the endpoint of §5 or §11 with its required reason: comment → remove it; Activity → delete it, remove a Media, reset title and description; athlete → reset name, bio or Avatar; every target → ban the author (absent if the author is an Administrator). Deleting the Activity or removing the comment closes the case by itself.

### 11. Activities in the backoffice ([#197](https://github.com/echimine/clone-strava/issues/197), amends ADR-019 §6)

- **List** (`GET /v1/admin/activities`): **every** Activity, private ones included; filters status, source, sport, visibility, period (`started_at`), athlete; search over title and the athlete's name or e-mail; default sort by creation date, newest first. No bulk action.
- **Detail** (`GET /v1/admin/activities/:id`): official values, status with `processing_error` and `processing_attempts`, **public trace only** (`activity_track`, already cut by the privacy zone; never the raw trace nor an imported file), Media thumbnails, comments, kudos, linked import, link to the athlete, Segment efforts read-only.
- **Actions**:
  - **Retraiter** (`POST …/:id/reprocess`, `activity.reprocess`, not a Sanction): `failed` only, back to `processing` and enqueued again, as ADR-019 §6 planned. A processed Activity is never recomputed from here.
  - **Supprimer l'Activité** (`DELETE …/:id`): the author's delete path (ADR-033 §6: hard delete, cascade, bucket prefix, `activities.activity.deleted`) without the author check; `409` while `processing`.
  - **Retirer un Média** (`DELETE …/:id/media/:mediaId`): the existing `delete-media` without the author check.
  - **Réinitialiser le titre et la description** (`POST …/:id/reset-text`): default title (`defaultActivityTitle`), description emptied.
  - **Retirer un commentaire** (`DELETE /v1/admin/comments/:id`): the existing soft delete without the author check.
- Excluded: free editing of title or description, changing visibility, a "hidden" state, removing kudos.

### 12. Premium in the backoffice ([#193](https://github.com/echimine/clone-strava/issues/193), [#204](https://github.com/echimine/clone-strava/issues/204), amends ADR-014, ADR-017)

- The user sheet section is called **"Premium"**, never "Abonnement" (a Follow in the app). It reads **only our tables**, never RevenueCat: state (Jamais abonné, Essai, Payant, Premium offert, Période de grâce, Problème de paiement, Résilié jusqu'au …, Expiré), detail (product, store, purchase, end or renewal, auto-renew, unsubscribe detected, Sandbox badge, last sync), history from `revenuecat_event` (type, date, product, no raw JSON), a link to the customer in RevenueCat, and **"Resynchroniser"** (enqueues `sync-subscription`).
- **Promotional Premium** ("Premium offert"): closed choice **1 / 3 / 6 / 12 months**, required reason; granting again replaces the end date (revoke then grant on RevenueCat's side); **removal** is immediate, with a required reason, and never touches an App Store subscription. Any account may receive it. No e-mail. Nothing is written by hand in `user_subscription`: the RevenueCat call triggers a webhook (`NON_RENEWING_PURCHASE` with `PROMOTIONAL`, then `CANCELLATION`/`EXPIRATION`), which triggers `sync-subscription`.
- **RevenueCat API v2 everywhere**: `GET …/customers/{id}` in `sync-subscription` (v1's read would create the customer), `actions/grant_entitlement` (`expires_at`) and `actions/revoke_granted_entitlement` in the API. One secret v2 key `REVENUECAT_API_KEY` (`sk_`), API and worker only, plus `REVENUECAT_PROJECT_ID` and the `entl…` id of `premium` in configuration.
- **Data model**: `promotional` added to the `store` and `period_type` enums; the key `(user_id, entitlement_id)` does not change: one `premium` row, **a mirror of the entitlement as RevenueCat computes it** (the source that expires last). `isPremium` is unchanged.
- **List and dashboard**: the Premium filter of the users list becomes Payant / Essai / Premium offert / Problème de paiement / Résilié / Expiré, with an "Fin" column; a "Premium offerts actifs" tile joins the Growth band.
- **Without a key**, "Offrir", "Retirer" and "Resynchroniser" are disabled with "RevenueCat non configuré"; the code is written against v2 and tested with mocked responses.

### 13. Account deletion ([#192](https://github.com/echimine/clone-strava/issues/192), [#193](https://github.com/echimine/clone-strava/issues/193), [#202](https://github.com/echimine/clone-strava/issues/202), amends ADR-021 §2 rule 7, ADR-035)

- **Immediate and final**: no grace period, no undo. One service, called from the app and from the backoffice.
- **iOS**: a red "Supprimer mon compte" button at the bottom of **Réglages**; a confirmation screen listing what will be erased and repeating the `SignOutWarning` lines; with an active paid subscription, the warning "Votre abonnement continue d'être facturé par Apple" and "Gérer mon abonnement" (`manageSubscriptionsSheet`), **without blocking**; re-verification by a **Sign-in code sent to the account's e-mail** (Google accounts included), online only. Afterwards: local sign-out cleanup, back to Welcome with "Compte supprimé". The code goes through the existing email OTP plugin; the exact endpoints are in the spec.
- **Erased**: everything through the existing SQL cascade (account, sessions, profile, Activities and traces, Media, comments and kudos on others' Activities, Follows, Blocks, Efforts, Itineraries, local subscription). Two exceptions, keeping nothing identifying: **Segments they created stay**, without creator ("Créateur supprimé"), because their leaderboards belong to the others too; **Reports they sent stay**, without reporter ("Athlète supprimé") and without their note, and their cases stay to review. Cases about them close as "Cible supprimée" (§10). Audit entries stay (§3).
- **Execution**: in the API, synchronously, sessions revoked and the user removed through `auth.api.removeUser` (cascade), then the audit entry, then the e-mail job (§4) and a **`delete-account` job** in a new **`accounts`** queue owned by `users`, carrying what it needs since the account is gone. The job is idempotent with retries: it deletes the three bucket prefixes (ADR-037 §11), then the RevenueCat customer (asynchronous on their side; it does not cancel the Apple subscription), then the PostHog person **last** (`persons/bulk_delete` by `distinct_id` = `user.id`, with a personal key `POSTHOG_PERSONAL_API_KEY` scoped `person:write` on the EU host), and writes a second audit entry, author "Système", when done. A RevenueCat webhook for a deleted account is ignored.
- **Trace**: an audit entry "Compte supprimé" with the `userId` and the origin (by the athlete without author, or the Administrator with the reason); no e-mail or name kept. No PostHog event.
- **E-mail**: one "Votre compte Nervo a été supprimé" in both cases; with the reason and contact address when it is a Sanction.
- **Backoffice**: `DELETE /v1/admin/users/:id { reason }`, a Sanction confirmed by **typing the athlete's name**. An Administrator cannot delete their account from the app (`403`, "Un administrateur ne peut pas supprimer son compte"). A banned athlete has no access to the button: they write to the contact address and an Administrator deletes the account (reason "Demande de l'athlète").
- The Privacy Policy draft (ADR-035 §9) mentions the two exceptions.

### 14. Jobs ([#194](https://github.com/echimine/clone-strava/issues/194), [#203](https://github.com/echimine/clone-strava/issues/203), amends ADR-011, ADR-019 §8)

- **Custom endpoints** `/v1/admin/queues/*` behind the guards, over a whitelist of queues in `contracts`: `activities`, `imports`, `segments`, `subscriptions`, `avatars`, `bucket-sweep` (`BUCKET_SWEEP_QUEUE_NAME` moves to `contracts`), `accounts`, `emails`. **No Bull Board in production**: it would bypass the guards, break behind the Next rewrite and expose `obliterate`; it stays a one-off tool over an SSH tunnel.
- **"Jobs" screen, two tabs**, opening on "Échecs":
  - **Échecs** (business view): failed Activities with "Retraiter"; failed imports with "Retraiter" (existing endpoint); **failed recomputations**, i.e. processed Activities whose `computed_for_sport_type_code` differs from `sport_type_code`, with "Recalculer", which enqueues `reprocess-activity` under a **new job id** (the old id blocks the sweep). Each list has "Retraiter les N en échec": a confirmation with the count, then a loop over the unit domain action, **500 at most per click**, returning how many were relaunched. No checkboxes.
  - **Files** (technical view): per queue, counts by state, pause state and failed jobs (paginated); the schedulers (`reconcile-activities`, `bucket-sweep`) with their rhythm and next run. Actions: retry one failed job (`resetAttemptsMade: true`), retry every failure of a queue, pause, resume. Raw retry is **refused** for `process-activity` and `import-activity` (it would do nothing outside `processing`); the screen points to "Retraiter". **No job deletion**, no `drain`, no `obliterate`. A failed job's detail shows name, id, queue, `failedReason`, folded stack trace, attempts, dates, and its data read-only with links to an Activity or athlete.
- All these actions are recorded, without reason; a batch gives **one entry** with the count and ids in `details`.
- **Retention everywhere**: completed `{ age: 7 days, count: 1000 }`, failed `{ age: 30 days, count: 5000 }`, the two schedulers' templates and `match-segments` included (which moves to `DEFAULT_JOB_RETRY`). A one-off `clean` of the `reconcile-activities` jobs already piled up in production. The durable history stays in the database.
- No alert on rising failures: the "À traiter" counter is enough.

### 15. Dashboard ([#196](https://github.com/echimine/clone-strava/issues/196))

- **Database only**, through `GET /v1/admin/stats/todo` and `GET /v1/admin/stats/growth?period=7d|30d|90d`; computed **on the fly**; app usage stays in PostHog (an "Ouvrir PostHog" link). Administrators and `sandbox` subscriptions are excluded; banned athletes stay counted.
- **"À traiter"** (current state, each tile opens its screen, refreshed every 60 s and on tab focus): open cases and the age of the oldest (red past 24 h); failed Activities; failed imports in the last 7 days; failed jobs; Efforts to review (§16).
- **"Croissance"** (period 7/30/90 days, 30 by default, each tile with its change versus the previous period): sign-ups; **Active athletes** (at least one Activity started in the period, glossary); Activities split recorded / imported / manual; Premium (paying and trials now, trials started and new paying in the period, Promotional Premium active); engagement (kudos, comments, Follows, Media added). An Activity's date is `started_at`, never `created_at`.
- One line chart per day with two series (sign-ups, Activities), with shadcn Chart (Recharts) added to `packages/ui`.

### 16. Segments and Suspicious efforts ([#198](https://github.com/echimine/clone-strava/issues/198))

- **Athletes create Segments in the app** on another map ("Segments dans l'app"), which also builds matching and leaderboards. That map adds `segment.created_by` (`on delete set null`, §13). Until it ships, the backoffice Segments screens have nothing to show.
- **Suspicious effort**: an Effort whose average speed on the Segment exceeds a **maximum set per sport** (in code, listed in the spec, no settings screen). Too slow is not detected. Efforts of `private` Activities are not checked.
- **States** on `segment_effort`: `valid`, `suspicious` (**stays in the leaderboard** until decided), `rejected` (out of the leaderboard, ranks recomputed). Accept (`valid`, never suspicious again), reject, restore. Rejecting is **not a Sanction**: optional reason, recorded. The decision stays attached to the Activity–Segment pair while the Effort exists, even if matching is replayed and its time changes.
- **Segments page**, two tabs: **"Efforts à vérifier"**, grouped by Activity, oldest first, with a "top of the leaderboard only" filter, the athlete, sport, date and public trace, and per Effort the Segment, time, speed, threshold exceeded and current rank; accept or reject one Effort or all of an Activity's. **"Segments"**: list and sheet (path, distance, grade, leaderboard, Efforts with their state). **Renaming or deleting** a Segment is a Sanction toward its creator.
- The matching built by the other map must respect these rules.

### 17. Audit actions and endpoints

| Area | Endpoint | Audit action | Reason |
|---|---|---|---|
| Users | `POST /v1/admin/users/:id/ban` `{ duration, reason }` / `unban` `{ reason }` | `user.ban` / `user.unban` | required |
| | `POST …/:id/sign-out` `{ reason }` | `user.sign_out` | required |
| | `POST …/:id/reset-name` / `reset-bio` / `reset-avatar` `{ reason }` | `user.name.reset` / `user.bio.reset` / `user.avatar.reset` | required |
| | `PUT …/:id/role` `{ role, reason? }` | `user.role.grant` / `user.role.revoke` | optional |
| | `DELETE /v1/admin/users/:id` `{ reason }` | `user.delete` | required |
| Premium | `POST …/:id/premium/sync` | `premium.sync` | none |
| | `POST` / `DELETE …/:id/premium/promotional` `{ duration?, reason }` | `premium.grant` / `premium.revoke` | required |
| Activities | `POST /v1/admin/activities/:id/reprocess`, `…/recompute` | `activity.reprocess` / `activity.recompute` | none |
| | `DELETE …/:id`, `DELETE …/:id/media/:mediaId`, `POST …/:id/reset-text` `{ reason }` | `activity.delete` / `media.remove` / `activity.text.reset` | required |
| | `DELETE /v1/admin/comments/:id` `{ reason }` | `comment.remove` | required |
| Batches | `POST /v1/admin/activities/reprocess-failed`, `…/recompute-stale`, `/v1/admin/activity-imports/reprocess-failed` | `activity.reprocess.batch`, `activity.recompute.batch`, `import.reprocess.batch` | none |
| Queues | `POST /v1/admin/queues/:name/jobs/:id/retry`, `…/:name/retry-failed`, `…/:name/pause`, `…/:name/resume` | `queue.job.retry`, `queue.retry_failed`, `queue.pause`, `queue.resume` | none |
| Reports | `POST /v1/admin/reports/:caseId/resolve` / `dismiss` `{ note? }` | `report.resolve` / `report.dismiss` | optional |
| Segments | `POST /v1/admin/segment-efforts/:id/accept` / `reject` / `restore` (and per Activity) | `effort.accept` / `effort.reject` / `effort.restore` | optional |
| | `PATCH` / `DELETE /v1/admin/segments/:id` `{ name?, reason }` | `segment.rename` / `segment.delete` | required |
| Better Auth hooks | — | `admin.two_factor.enable` / `admin.two_factor.disable` | — |

Reads (`GET`) are not recorded. `POST /v1/admin/activity-imports/:id/reprocess`, which exists, is decorated as `import.reprocess`.

### 18. Data model (amends ADR-017, ADR-021 §1, §2)

| Module | Layer | New or changed tables |
|---|---|---|
| `audit` (new) | 0 | `audit.admin_audit_entry (id, actor_id, action, target_type, target_id, subject_user_id, reason, details jsonb, request_id, created_at)`, no foreign key; indexes on `(subject_user_id, created_at)`, `(actor_id, created_at)`, `(action, created_at)` |
| `moderation` (new) | 0 | `moderation.report_case (id, target_type, target_id, target_user_id, status open\|actioned\|dismissed\|target_gone, opened_at, closed_at, closed_by, close_note)`, unique partial `(target_type, target_id) where status = 'open'`; `moderation.report (id, case_id, reporter_id → user on delete set null, reason, note, snapshot jsonb, created_at)`, unique `(reporter_id, case_id)` |
| `social` | 1 | `social.athlete_block (blocker_id, blocked_id, created_at)`, unique pair, cascade |
| `segments` | 3 | `segment_effort.status valid\|suspicious\|rejected`; `segment.created_by` from the Segments-in-app map |
| `subscriptions` | 0 | `promotional` in the `store` and `period_type` enums |
| `auth` | 0 | none: the Ban columns already exist |

`moderation` reacts to deletions of comments, Activities and users through domain events (ADR-021 §3). `users` owns the `accounts` queue and the `delete-account` job. The `emails` queue's processor calls `notifications`.

### 19. Out of scope

- Impersonation: the backoffice is web, the app is iOS; the user sheet is enough for support.
- Administration sub-roles (moderator, support).
- Segments in the iOS app: creation, matching and leaderboards (another map); the Segment editor prototype ([#205](https://github.com/echimine/clone-strava/issues/205)).
- Free search of comments: a comment is found through its Activity or a Report.
- Terms of use accepted in the app and a text filter before publication ([#207](https://github.com/echimine/clone-strava/issues/207)): the app will never be published.
- Removing the Measurement consent from the app (decided the same day, handled outside this map).
- Alerts on failed jobs, a revenue view (it stays in RevenueCat), a public legal page.

## Alternatives Considered

- **Bull Board mounted in the API**: a ready-made UI, but an Express middleware that skips `AdminGuard`, breaks behind the Next rewrite and offers `obliterate` and data editing. Rejected for custom endpoints that send Activity retries through the domain.
- **`listUsers` from Better Auth for the users list**: case-sensitive, one field, Better Auth tables only. Rejected for our own query joining the profile, Activities and Premium.
- **Closing the plugin's HTTP routes** (`disabledPaths`): cheap, but no Administrator uses the iOS app; the risk is accepted.
- **A "hidden" state for content and a Report threshold that hides automatically**: rejected; content is either there or deleted, and a threshold invites coordinated Reports.
- **A grace period before account deletion**: rejected for an immediate, final deletion with a code re-verification.
- **Anonymizing a deleted athlete's content**: rejected; everything goes, except Segments and sent Reports, which keep nothing identifying.
- **One-way Block** (Twitter's "mute"): rejected; a Block hides each from the other.
- **RevenueCat v1**: its read creates the customer and `duration` is deprecated. Rejected for v2.
- **Statistics from PostHog's query API**: consent made it undercount, and it double-counts what the database knows. Rejected for database counts.

## Consequences

### Positive

- Every admin action leaves one trace in one table, and a Sanction always says why, to the Administrator and to the athlete.
- One endpoint per domain action keeps the Activities screen, the moderation queue and the user sheet consistent.
- Ban, Reports and Blocks share one viewer filter, so a new read path only has to accept it.
- Account deletion is one service, with a clear rule for what survives and an idempotent job for everything outside the database.
- Queues become visible without Bull Board, and retries of Activities always go through the domain.

### Negative / Risks

- **Read-time hiding** puts an exclusion list on every read path; a forgotten path leaks a banned or blocked athlete's content.
- **The plugin's HTTP routes** still let an `admin` bearer bypass the strong session.
- **The audit entry is written after the action, outside its transaction**: a crash between the two loses the entry.
- **Counters are unchanged** by Bans and Blocks, so an athlete may see a count that does not match the visible list.
- **Promotional Premium cannot be tested** until the RevenueCat SDK is wired and a v2 key exists.
- **The Segments screens are empty** until the Segments-in-app map ships.
- **The deletion e-mail and job depend on the API surviving** the few milliseconds after the cascade; the `bucket-sweep` catches bucket leftovers, not RevenueCat or PostHog ones.

## References

- Specs: [#209 Journal d'audit et conventions des listes du backoffice](https://github.com/echimine/clone-strava/issues/209), [#210 Signaler et bloquer depuis l'app iOS](https://github.com/echimine/clone-strava/issues/210), [#211 Utilisateurs, fiche et Ban](https://github.com/echimine/clone-strava/issues/211), [#212 Activités dans le backoffice](https://github.com/echimine/clone-strava/issues/212), [#213 File de modération des Signalements](https://github.com/echimine/clone-strava/issues/213), [#214 Suppression de compte depuis l'app et le backoffice](https://github.com/echimine/clone-strava/issues/214), [#215 Premium dans le backoffice](https://github.com/echimine/clone-strava/issues/215), [#216 Écran Jobs, files de traitement et échecs](https://github.com/echimine/clone-strava/issues/216), [#217 Tableau de bord du backoffice](https://github.com/echimine/clone-strava/issues/217), [#218 E-mails à l'athlète après une Sanction](https://github.com/echimine/clone-strava/issues/218), [#219 Segments et Efforts suspects dans le backoffice](https://github.com/echimine/clone-strava/issues/219)
- Map: [Backoffice Nervo (#190)](https://github.com/echimine/clone-strava/issues/190) and its tickets [#191](https://github.com/echimine/clone-strava/issues/191)–[#208](https://github.com/echimine/clone-strava/issues/208)
- Research notes: [better-auth-admin-plugin.md](https://github.com/echimine/clone-strava/blob/research/better-auth-admin-plugin/docs/research/better-auth-admin-plugin.md), [app-store-ugc-account-deletion.md](https://github.com/echimine/clone-strava/blob/research/app-store-ugc-account-deletion/docs/research/app-store-ugc-account-deletion.md), [revenuecat-posthog-account.md](https://github.com/echimine/clone-strava/blob/research/revenuecat-posthog-account/docs/research/revenuecat-posthog-account.md), [bullmq-admin-queues.md](https://github.com/echimine/clone-strava/blob/research/bullmq-admin-queues/docs/research/bullmq-admin-queues.md)
- Better Auth admin plugin: https://www.better-auth.com/docs/plugins/admin
- RevenueCat API v2: https://www.revenuecat.com/docs/api-v2
- PostHog data deletion: https://posthog.com/docs/privacy/data-deletion
- BullMQ getters: https://docs.bullmq.io/guide/jobs/getters

## Links

- **Depends on**: [ADR-004](ADR-004-backoffice.md), [ADR-013](ADR-013-backoffice-architecture.md), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-022](ADR-022-authentication-better-auth.md), [ADR-035](ADR-035-onboarding-sign-in-code-paywall.md) (§3 strong admin session), [ADR-037](ADR-037-media-avatar-and-gallery.md) (§11 user prefixes)
- **Amends**:
  - [ADR-011](ADR-011-backend-worker.md): `accounts` and `emails` queues; retention 7 days/1,000 and 30 days/5,000 everywhere, schedulers and `match-segments` included.
  - [ADR-013](ADR-013-backoffice-architecture.md): admin list conventions (offset pagination with total, `q`, `sort`/`order`).
  - [ADR-014](ADR-014-revenuecat.md): RevenueCat API v2 for reading and Promotional Premium; one `sk_` v2 key.
  - [ADR-017](ADR-017-data-model.md): `audit` and `moderation` schemas, `social.athlete_block`, `segment_effort.status`, `promotional` in `store` and `period_type`.
  - [ADR-019](ADR-019-activity-creation-flow.md): §6 the reprocess endpoint is specified; §8 `match-segments` uses `DEFAULT_JOB_RETRY` and the Suspicious effort rules.
  - [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md): §1 `audit` and `moderation` modules, `athlete_block` in `social`; §2 both in layer 0, rule 7 the account deletion job and its two exceptions.
  - [ADR-022](ADR-022-authentication-better-auth.md): §3 the admin plugin is called through `auth.api.*` from `/v1/admin/*`; its HTTP routes stay exposed (accepted risk).
  - [ADR-023](ADR-023-transactional-email-resend.md): e-mails to athletes and Administrators beyond auth, `sendEmail` with `Reply-To`, `emails` queue.
  - [ADR-035](ADR-035-onboarding-sign-in-code-paywall.md): §9 the Privacy Policy mentions the two deletion exceptions; the "Supprimer mon compte" button is no longer out of scope.
- **Related**: [ADR-015](ADR-015-posthog.md), [ADR-029](ADR-029-activity-feed-and-card.md), [ADR-033](ADR-033-activity-detail-edit-delete.md), [ADR-034](ADR-034-activity-engagement-and-live-detail.md), [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md)
