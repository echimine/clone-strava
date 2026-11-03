# ADR-035: Onboarding, account creation by email code, and the unwired Paywall

- **Status**: accepted
- **Date**: 2026-11-02
- **Deciders**: echimine
- **Tags**: onboarding, auth, better-auth, paywall, revenuecat, analytics, posthog, privacy, mobile, ios, api

## Context

Today a person who opens Nervo without an account lands on `AuthFlowView` and types an email and a password (ADR-022 §1). Nothing learns who they are, nothing offers Premium, and the profile (`users.user_profile`) is never written. The wayfinder map [Onboarding, création de compte et Paywall](https://github.com/echimine/clone-strava/issues/105) worked out how a newcomer should get started instead. Each decision below is detailed in a closed ticket of that map, linked in [References](#references). The prototypes live on the throwaway branch `prototype/onboarding-screens`, which is never merged.

Facts the decisions depend on (code at `9987efd`, `better-auth@1.7.6`):

- Better Auth's `emailOTP` plugin signs in with two calls, `POST /api/auth/email-otp/send-verification-otp {email, type: "sign-in"}` then `POST /api/auth/sign-in/email-otp {email, otp, name?}`. The first valid code **creates the account** (`emailVerified: true`), and the response does not say whether it did. The session is set as a cookie, so the `bearer` plugin returns `set-auth-token` as it does today.
- Codes: 6 digits, valid 5 min, 3 attempts per code (then `TOO_MANY_ATTEMPTS`, `403`). Each resend rotates the code. They are stored in Redis only. The plugin's rate limit is per IP and per path (3 requests / 60 s on send and on verify), with nothing per email address.
- `twoFactor` only intercepts `/sign-in/email`. `AdminGuard` only checks the `twoFactorEnabled` flag. So a code (or Google, already today) gives an admin a session that passes the guard without a second factor.
- A first code on an existing account whose email was never verified **revokes all its `account` rows and sessions** (`revokeUnprovenAccountAccess`).
- `users.user_profile` has `first_name`, `last_name`, `birth_date`, `gender text`, but no row is ever created. Nothing stores sports, goals or level.
- `PostHogAnalyticsClient` hard-codes `optOut = true`, and `AnalyticsClient` only has `capture`. No permission request for notifications exists. The Live Activity does not need one.

## Decision

### 1. The getting-started flow

```
first launch: splash → Welcome + Measurement consent sheet
"Créer un compte": Onboarding (6 questions, "Voici ce qui vous attend", personalised loading)
                 → account screen (Google or email → Sign-in code)
                 → Onboarding answers sent → Paywall → notification prompt → home
"Se connecter":   account screen → Sign-in code → home
```

- The **Onboarding answers stay on the phone only** until a session exists. Nothing anonymous is ever stored on the server.
- The **Welcome** is a carousel of 3 full-width scenes (Live Activity on the lock screen, arrival celebration, `.gpx`/`.fit`/`.tcx` import). "Créer un compte" opens the Onboarding and "Se connecter" opens the account screen. The splash (ADR-032 §4) is unchanged.
- The **Onboarding** asks one question per screen, in this order: name → birth date → gender → sports → goals → level. First and last name are required. The minimum age is 15. Gender has 4 values (including "prefer not to say"). Sports are the active `sport_type` codes, at least one, kept in the order they were picked. Goals are optional (0 to 6). Level has 4 values. An interrupted Onboarding resumes where it stopped.
- **"Se connecter" skips the Onboarding and the Paywall**, unless that sign-in has just created the account: if `user.createdAt` in the sign-in response is **less than 2 minutes old**, the app sends the person through the Onboarding as if they had tapped "Créer un compte". An existing account is never sent through the Onboarding.
- The account screen is the same for both entries (only the title changes): Google, or an email that receives a **Sign-in code**. There is no Apple button (blocked by ADR-022 §1) and no reserved slot for one. There is no "J'ai déjà un compte" link: signing in with the same address or Google account at the end of the Onboarding simply signs in (§2).

### 2. Sign-in by email code, no password in the app (amends ADR-022 §1, §4, ADR-023)

- The app signs in and signs up with **Google or an email + 6-digit Sign-in code**. There is no password. The `emailOTP` plugin is added with its defaults (6 digits, 5 min, 3 attempts, `resendStrategy: "rotate"`) and `storeOTP: "hashed"`, as for the admin OTP (ADR-022 §5). The `bearer` flow and `APIAuthRepository` token handling are reused unchanged.
- At account creation by code, the app passes "Prénom Nom" from the Onboarding as `name`, which gives the backoffice a real `user.name`. Better Auth ignores it when the account already exists.
- **Same email, same account**, whichever way the person signs in: Google then code signs straight in, and code then Google links implicitly when Google confirms `email_verified`.
- **Password sign-up is closed** everywhere (`emailAndPassword.disableSignUp: true`), except in the API's test instance (an option of `createAuthInstance`) so `auth-flows.spec` and `admin-2fa.spec` keep working. **Password sign-in stays** for the backoffice and admin 2FA. On iOS, `AuthFlowView`, `SignInView`, `SignUpView` and the whole email + password path (repository, service, store, tests) are deleted. `RootView` shows the Welcome when signed out.
- Sign-in code screen: 6 boxes with `.oneTimeCode` autofill, automatic submit at the 6th digit, "Ouvrir Mail", and "Recevoir un nouveau code" disabled for 30 s (consistent with 3 sends / 60 s). A wrong code clears the boxes. An expired code or a 3rd failure disables them and promotes the resend button. The number of attempts left is not shown.
- Rate limiting: the plugin's per-IP rules on the two OTP paths are kept as they are, next to ADR-022 §4's rules on `/sign-in/email` and `/sign-up/email`.
- **Resend** (ADR-023) gets a fourth handler, `emailOTP.sendVerificationOTP({ email, otp, type })`, with a React Email template `renderSignInCodeEmail`. It receives no `user`, so its idempotency key is `sign-in-code/<email>-<otp>`.
- **Development only** (`NODE_ENV=development`): the API logs every code, and `@stravaclone.test` addresses get the fixed code `000000` (`generateOTP`) without any email being sent. UI tests and `test.map@stravaclone.test` rely on it. `scripts/create-test-user.sh` is deleted. Existing dev accounts with a password and an unverified email lose their password and Google links at their first code (`revokeUnprovenAccountAccess`). This is accepted, with no migration.

### 3. Admin rights require a password + 2FA session (amends ADR-022 §5)

- **Only a session opened by password + second factor carries admin rights.** The limit is on the session, not the account: an admin can use the iOS app with a code or Google, but `/v1/admin/*` refuses that session.
- A session field **`authMethod`** (`password_2fa` | `password` | `email_otp` | `google`) is set by `databaseHooks.session.create.before` from `ctx.path`: `/two-factor/verify-*` gives `password_2fa`, `/sign-in/email` and `/sign-up/email` give `password`, `/sign-in/email-otp` gives `email_otp`, and `/callback/google` and `/sign-in/social` give `google`. An unknown path counts as weak.
- `AdminGuard` refuses in this order: not admin → `403`; 2FA not enabled → `ADMIN_2FA_REQUIRED`; weak session → **`ADMIN_STRONG_SESSION_REQUIRED`** (`403`, the message asks the admin to sign in again on the backoffice with password + 2FA). `GET /v1/me` is unchanged.
- Google loses ADR-022 §5's exception ("OAuth carries Google's strength"). The backoffice does not offer Google, so that exception only served the hole: an iOS bearer token used on `/v1/admin`. Refusing bearer tokens on `/v1/admin` would not have been enough, because a code entered in a browser yields a cookie.
- Existing sessions have no `authMethod` and count as weak. There is no migration: each admin signs in again once.
- **Deployment order**: the backoffice has no 2FA screens today (neither for entering the second factor nor for enabling it). [Écrans 2FA du backoffice](https://github.com/echimine/clone-strava/issues/114) must ship **before** this rule is deployed, or no admin can reach the backoffice.

### 4. The Onboarding answers become the profile (amends ADR-017)

There is no "Onboarding answers" table. Once received, the answers are simply profile fields:

| Answer | Storage |
|---|---|
| First name, last name | `users.user_profile.first_name` / `last_name` (existing, stay nullable for older accounts) |
| Birth date | `users.user_profile.birth_date` (existing) |
| Gender | `users.user_profile.gender` changes from `text` to the enum `users.gender` (`male`, `female`, `non_binary`, `undisclosed`), nullable: `null` = never asked. The column is empty today, so the migration copies no data. |
| Level | new `users.user_profile.level`, enum `users.athlete_level` (`beginner`, `intermediate`, `advanced`, `professional`), nullable |
| Goals | new `users.user_profile.goals`, `users.goal[]` (`compete`, `discover_routes`, `health`, `meet_athletes`, `train_for_event`, `build_habit`), nullable: `null` = never went through the Onboarding, `[]` = skipped |
| Practiced sports | new table **`users.user_sport`** (`user_id` → `auth.user` **on delete cascade**, `sport_code` → `sports.sport_type.code`, `position`), primary key `(user_id, sport_code)`; `position` keeps the order of selection |

- The profile name is the **only source of the displayed name** (already the rule of `AthleteIdentities`: profile first, `user.name` as fallback). `user.name` is **never rewritten**. It stays a technical account name for the backoffice and fallback display.
- There is **no "Onboarding completed" marker** (`onboarded_at`): sending the answers is idempotent (§5), and the PostHog funnel covers the analysis.

### 5. Sending the Onboarding answers (amends ADR-008)

- **`PUT /v1/me/onboarding-answers`** (`SessionGuard`, Zod contract in `packages/contracts`) is called once a session exists. It is the same call after Google and after a code, and nothing goes through Better Auth's `additionalFields` or hooks. It writes `user_profile` and `user_sport` in **one transaction** in `packages/core/users`. It is not a general profile edit, which will get its own endpoint later.
- The server validates the answers against §1 (required names, age ≥ 15, enum values, at least one **active** sport code, goals without duplicates).
- **It only fills what is empty**: names, birth date, gender, level and goals are written only where they are `null`, and sports only if the user has none. It answers **`204` in every case**. Consequences: a new account gets everything written, an account that already went through the Onboarding gets nothing written, and an older account that never did is completed without touching a name it already has. The app never decides any of this: it always sends.
- **iOS**: a one-row GRDB table **`onboarding_draft`** (answers + current step) is the only local copy and lets an interrupted Onboarding resume. Sending is tried right after sign-in. On failure (network, timeout, `5xx`), a **`submit_onboarding_answers`** operation goes into `sync_operation` with no payload (it re-reads the draft), retried as in ADR-008 and ADR-031 (2 s to 300 s, no attempt limit). **The flow never waits for it**: the Paywall does not wait for the answer.
- The draft and the operation are deleted on `204`, on any `4xx` other than `401` (the error is logged and nothing is shown), and on sign-out. A `401` refreshes the session and retries, as usual.

### 6. The Paywall, shown but not wired (amends ADR-014)

- The Paywall is shown **once**, right after sign-in, to **everyone who went through the Onboarding** (new or existing account, since the app does not tell them apart). It is never shown on the "Se connecter" path.
- **Nothing is sold yet**: "Démarrer l'essai", "Passer" / "Non merci" all continue to the notification prompt, and no Premium is granted. "Restaurer les achats" shows a "not wired" message. The hard-coded content is a 30-day free trial on both offers, then **€59.99/year** (pre-selected) or **€9.99/month**, with the price after the trial readable outside the small print (App Store 3.1.2). It also lists 5 Premium benefits and promises a reminder 2 days before the trial ends, which we will have to send ourselves once purchases are real (Apple does not).
- **Three layouts**, all kept for A/B testing through RevenueCat Experiments (ADR-016): `A` Strava (timeline of the trial), `B` AllTrails (offer cards + Free/Premium table), and **`C` Duolingo with a real map** (an actual ride, segment trophy and leaderboard), which is the **default**. The layout comes from the offering's **`layout` metadata**, as are prices and trial length.
- **Port `SubscriptionService`** in `Features/Paywall/Domain`: `paywallOffering()` (offers, recommended offer, `layout`), `startTrial(offer)`, `restorePurchases()`. The screen only knows this port. Today an **unwired adapter** (hard-coded offers, `layout = C`, purchase → unavailable) is created in `Di.swift` in place of `TODO(ADR-014)`. Tomorrow a RevenueCat adapter in `Infrastructure/` fills the same types from the current offering, without changing the screen.
- **Offers that fail to load** (only possible once RevenueCat is wired): the Paywall is **skipped** without blocking the end of the flow, and it is not shown again.
- The legal footer links to the Terms and the Privacy Policy (§9).

### 7. Notification permission, asked once after the Paywall

- After the Paywall (whether trial tapped, dismissed, or skipped for lack of offers), and **only on the Onboarding path**, Nervo shows its own **priming screen** before iOS's one-time system prompt: a fake iOS banner ("Nervo · Léa a donné un kudos à votre Sortie du matin"), the title "Ne manquez rien", two lines (kudos and comments; a reminder before the trial ends), "Activer les notifications" (opens the system prompt) and "Plus tard" (continues without spending it). Then the home screen.
- If iOS already reports the permission as granted or denied (for example after creating a second account on the same phone), the step is **skipped silently**, with no link to Settings.
- The app requests **authorization only** (alert, sound, badge). It does not register with APNs, sends no token to the server, and does not use provisional authorization: real push notifications come later (ADR-006, ADR-011).
- Nothing asks again after "Plus tard". A contextual request (for example at the first kudos received) will come with real push notifications.
- If the app is killed on the Paywall or on the priming screen, the next launch goes straight to the home screen. These steps are not resumed, and nothing on the phone remembers them.

### 8. Measurement consent and the funnel (amends ADR-015)

- **Measurement consent** is asked on first launch, 0.5 s after the splash, in a sheet over the Welcome that cannot be swiped away. "Accepter" and "Refuser" have the same size and weight, nothing is pre-selected, and the Privacy Policy link sits underneath. Refusing changes nothing else in the app.
- The choice is **stored on the phone, per device**, not tied to the account, and survives sign-out. It can be changed in a new **"Confidentialité"** section of the existing "Compte" screen (Profile tab), which also links the Terms and the Policy. There is no Settings screen (*amended by [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md) §10*: the "Compte" form becomes the Réglages screen, opened from the profile's gear). `AnalyticsClient` gains `optIn()`, `optOut()`, `identify(userId)` and `reset()`. Re-enabling calls `optIn()`, then `identify` when a session exists.
- **`identify(userId)` is called as soon as a session exists** (after the code, after Google, at launch with an existing session), **before** the `PUT` of the answers. `reset()` is called at sign-out.
- App events live in `enum AnalyticsEvent`: `welcome_viewed`, `onboarding_started`, `onboarding_step_viewed {step, resumed}`, `onboarding_completed {sportCodes, goals, goalsCount, level}`, `auth_screen_viewed {entry}`, `auth_method_chosen {method}`, `auth_google_cancelled`, `email_code_requested {resend}`, `email_code_failed {reason}`, `signed_in {method, isNewAccount}`, `paywall_viewed {layout, isNewAccount}`, `paywall_skipped {reason}`, `paywall_trial_tapped {layout, period}`, `paywall_dismissed {layout}`, `notification_prompt_viewed`, `notification_permission_answered {granted}` (only on the system prompt's answer) and `notification_permission_deferred` ("Plus tard"). Server events live in `packages/contracts/src/analytics/catalog.ts`: `user_signed_up {method}` (Better Auth hook at account creation) and `onboarding_answers_received` (on `204` when something was filled).
- **Never** name, email or its domain, birth date or age, or gender. Lists are sent as joined strings, so `AnalyticsValue` is not widened. PostHog only measures the Paywall and never drives it (ADR-016).
- Two PostHog funnels ship with the spec. The first goes `welcome_viewed` → `onboarding_started` → `onboarding_completed` → `signed_in {isNewAccount: true}` → `paywall_viewed` → `paywall_trial_tapped` or `paywall_dismissed` → `notification_prompt_viewed` → `notification_permission_answered`. The second goes `email_code_requested` → `signed_in {method: email}`.
- **Accepted gap**: the server does not know the choice made on the phone and sends its events for everyone. [Le serveur respecte le consentement à la mesure](https://github.com/echimine/clone-strava/issues/115) fixes this **before publication**.

### 9. Personal data

- Birth date and gender are **never shown to other athletes**: no response about another athlete carries them (`FeedAuthor` stays `{id, displayName, avatarUrl}`). Each of these two Onboarding screens carries one line explaining it ("Sert à vérifier votre âge. Elle n'apparaît jamais sur votre profil.", "Visible par vous seul."). There is no checkbox and no long GDPR text.
- Account deletion follows ADR-021 §2 (rule 7): everything cascades, with no anonymisation. That includes `user_sport` (§4). The phone's draft is already deleted at sign-out.
- **Terms of use and Privacy Policy** are two **Markdown files embedded in the app**, shown in a sheet. They work offline and need no hosting. They open from the Paywall footer, from the account screen ("En continuant, vous acceptez les Conditions d'utilisation et la Politique de confidentialité de Nervo.", no checkbox) and from the "Confidentialité" section. The spec fixes their outline. The implementer writes a first draft marked as one.

### 10. Out of scope

Sign in with Apple (ADR-022 §1); real purchases and granting Premium; real push notifications, the end-of-trial reminder, and asking again after "Plus tard"; Strava screens we dropped (privacy, follow suggestions, "Welcome, Sam!", home checklist); forcing the Onboarding on existing accounts; an App Review demo account; the backoffice 2FA screens ([#114](https://github.com/echimine/clone-strava/issues/114), a prerequisite of §3); server-side consent ([#115](https://github.com/echimine/clone-strava/issues/115)); the "Supprimer mon compte" button; a screen to view or edit one's profile; legal review of the Terms and Policy, a contact address, and a public URL for App Store Connect.

## Alternatives Considered

| Option | Why rejected |
|---|---|
| Keep email + password in the app | Extra friction and a password to forget, while Strava and most consumer apps sign in by code; the code also verifies the email for free |
| Store anonymous Onboarding answers on the server before the account exists | Personal data with no account to attach it to, delete it with or claim it from |
| Paywall before account creation | No user to attach a future purchase to; RevenueCat identifies by our user id (ADR-014) |
| Send the answers inside the sign-up request (`additionalFields` or a Better Auth hook) | Differs between Google and code, and ties profile writes to the auth library; a separate idempotent `PUT` serves both |
| A separate table of Onboarding answers, or an `onboarded_at` marker | The answers are the profile; filling only empty fields makes replays harmless without a marker |
| Block code and Google sign-in for admin accounts | Admins could no longer use the iOS app, which has no password |
| Refuse bearer tokens on `/v1/admin` | A code entered in a browser yields a cookie, so the hole stays open |
| Ask iOS for the notification permission directly | iOS shows its prompt once; a refusal there can only be undone in Settings |
| Remember post-sign-in steps to resume the Paywall and the priming screen | A rare case, and nothing is lost: the system prompt is not spent |
| Host the Terms and Policy on a website | Needs hosting and a domain now; embedded Markdown works offline. A public URL is still needed before publication |

## Consequences

### Positive

- One flow, two entries: the same account screen and Sign-in code serve "Créer un compte" and "Se connecter", and the same `PUT` serves Google and code.
- The server holds nothing about a person until they have an account, and only what the profile lacks afterwards.
- The admin backoffice is protected by the session's strength, not by a flag on the account, which closes a hole that already existed with Google.
- The Paywall ships and is measured now, and wiring RevenueCat later only swaps the `SubscriptionService` adapter. The A/B test needs no new release.

### Negative / Risks

- **No limit per email address** on code sends, only per IP: someone can make Nervo send codes to an address from several IPs. Watch it with Resend's logs; add a per-email rule if it happens.
- **"Account created less than 2 minutes ago"** is a heuristic: a clock skew, or someone abandoning the flow for over 2 minutes between the code and the response, sends a new account straight to the home screen without the Onboarding.
- **Deployment order**: §3 locks admins out until the backoffice 2FA screens exist.
- **Before publication** (the app is not published): Sign in with Apple, a "Supprimer mon compte" button (required by Apple), server-side consent (#115), and legal review, contact address and public URL for the Terms and Policy.
- **Dev accounts with a password** lose their password and Google links at their first code.

## References

- Wayfinder map: [Onboarding, création de compte et Paywall](https://github.com/echimine/clone-strava/issues/105)
- [Better Auth emailOTP avec bearer et iOS](https://github.com/echimine/clone-strava/issues/108) (research: `docs/research/better-auth-email-otp.md` on branch `research/better-auth-email-otp`)
- [Contenu des écrans d'Onboarding](https://github.com/echimine/clone-strava/issues/111), [Écran Welcome](https://github.com/echimine/clone-strava/issues/116)
- [Stockage serveur des Onboarding answers](https://github.com/echimine/clone-strava/issues/106), [Envoi des Onboarding answers à la création du compte](https://github.com/echimine/clone-strava/issues/107)
- [Parcours de création de compte et de connexion par code](https://github.com/echimine/clone-strava/issues/109) (mock-up: https://claude.ai/artifact/CJFWzkktBCCJu3fTBrBS8R)
- [Design du Paywall non branché](https://github.com/echimine/clone-strava/issues/110)
- [2FA admin contournée par la connexion par code et Google](https://github.com/echimine/clone-strava/issues/112)
- [Événements PostHog du funnel Onboarding, compte et Paywall](https://github.com/echimine/clone-strava/issues/113)
- [Données personnelles de l'Onboarding](https://github.com/echimine/clone-strava/issues/117), [Permission notifications après le Paywall](https://github.com/echimine/clone-strava/issues/118)
- Better Auth email OTP plugin: https://better-auth.com/docs/plugins/email-otp
- App Store Review Guidelines 3.1.2 (subscriptions), 4.8 (Sign in with Apple), 5.1.1(v) (account deletion)

## Links

- **Depends on**: [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md), [ADR-022](ADR-022-authentication-better-auth.md), [ADR-023](ADR-023-transactional-email-resend.md), [ADR-032](ADR-032-brand-and-motion-design.md)
- **Amends**: [ADR-008](ADR-008-mobile-offline-sync.md) (`submit_onboarding_answers` operation), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md) (`users` owns `user_sport`, §1 and §7), [ADR-014](ADR-014-revenuecat.md) (unwired `SubscriptionService` adapter, layouts `A`/`B`/`C` with `C` by default, Paywall skipped when offers fail to load), [ADR-015](ADR-015-posthog.md) (consent stored per device, "Confidentialité" section, server events ignore consent for now), [ADR-017](ADR-017-data-model.md) (`gender` enum, `level`, `goals`, `users.user_sport`), [ADR-022](ADR-022-authentication-better-auth.md) (§1 sign-in by email code and password sign-up closed, §4 OTP rate limits, §5 admin rights need a password + 2FA session and Google loses its exception), [ADR-023](ADR-023-transactional-email-resend.md) (Sign-in code email)
- **Amended by**: [ADR-036](ADR-036-athlete-profile-follows-and-activity-analysis.md) (§8 Réglages screen)
- **Related**: [ADR-006](ADR-006-mobile-stack.md), [ADR-007](ADR-007-mobile-architecture.md), [ADR-011](ADR-011-backend-worker.md), [ADR-016](ADR-016-experimentation.md), [ADR-031](ADR-031-live-recording-on-ios.md)
