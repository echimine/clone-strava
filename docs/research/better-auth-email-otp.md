# Research: Better Auth `emailOTP` with bearer and iOS

- **Ticket**: [#108](https://github.com/echimine/clone-strava/issues/108) (map [#105](https://github.com/echimine/clone-strava/issues/105))
- **Date**: 2026-11-02
- **Version researched**: `better-auth@1.7.6` (pinned in `packages/core`, `apps/api`, `apps/admin` `package.json`)
- **Scope**: facts only. No design decision is made here; options and trade-offs are listed where a fact opens one.

## Sources

Primary sources, in order of authority:

1. **Installed package source** (`node_modules/.pnpm/better-auth@1.7.6_*/node_modules/better-auth/dist/`), abbreviated `dist/` below:
   - `dist/plugins/email-otp/{index,routes,otp-token,utils,types.d,error-codes}.mjs`
   - `dist/plugins/bearer/index.mjs`
   - `dist/plugins/two-factor/index.mjs`, `dist/plugins/two-factor/otp/index.mjs`
   - `dist/db/internal-adapter.mjs`, `dist/db/revoke-unproven-account-access.mjs`
   - `dist/oauth2/link-account.mjs`, `dist/api/routes/sign-in.mjs`, `dist/api/routes/sign-up.mjs`
   - `dist/api/rate-limiter/index.mjs`, `dist/api/middlewares/origin-check.mjs`, `dist/context/helpers.mjs`
   - `@better-auth/core@1.7.6` `dist/social-providers/google.mjs`
2. **Official docs**: <https://www.better-auth.com/docs/plugins/email-otp> (source: <https://github.com/better-auth/better-auth/blob/main/docs/content/docs/plugins/email-otp.mdx>), fetched via Context7 on 2026-11-02. They match the 1.7.6 source on every point checked below.
3. **This repo**: `packages/core/src/auth/create-auth-instance.ts`, `packages/core/src/auth/auth-secondary-storage.ts`, `apps/api/src/main.ts`, `apps/api/src/auth/admin.guard.ts`, `apps/admin/src/app/(auth)/login/page.tsx`, `apps/mobile/StravaClone/Features/Auth/Infrastructure/APIAuthRepository.swift`, ADR-022, ADR-023.

## 1. Routes and payloads

The plugin is `emailOTP` from `better-auth/plugins`. All routes are served under `/api/auth` (mounted with `toNodeHandler` in `apps/api/src/main.ts`), so no NestJS work is needed to expose them.

| Purpose | Route | Body | Response |
|---|---|---|---|
| Send a code | `POST /api/auth/email-otp/send-verification-otp` | `{ "email": string, "type": "sign-in" \| "email-verification" \| "forget-password" }` | `{ "success": true }` (always, see below) |
| Sign in **or sign up** with the code | `POST /api/auth/sign-in/email-otp` | `{ "email": string, "otp": string, "name"?: string, "image"?: string, ...additionalFields }` | `{ "token": string, "user": User }` + session cookie |
| Check a code without consuming it | `POST /api/auth/email-otp/check-verification-otp` | `{ email, type, otp }` | `{ "success": true }` |
| Verify email (no sign-in) | `POST /api/auth/email-otp/verify-email` | `{ email, otp }` | `{ status, token \| null, user }` |
| Password reset by code | `POST /api/auth/email-otp/request-password-reset`, `POST /api/auth/email-otp/reset-password` | — | — |
| Change email by code | `POST /api/auth/email-otp/request-email-change`, `POST /api/auth/email-otp/change-email` (only if `changeEmail.enabled`) | — | — |

Source: `dist/plugins/email-otp/routes.mjs` (`sendVerificationOTP`, `signInEmailOTP`, `checkVerificationOTP`, `verifyEmailOTP`, …); the `type: "change-email"` value is rejected on `send-verification-otp` (dedicated route instead).

### There is no separate "sign-up" type

- The `type` enum is `email-verification | sign-in | forget-password | change-email`. Sign-up **is** `type: "sign-in"`.
- `POST /sign-in/email-otp` looks the user up by email after consuming the code. If none exists **and `disableSignUp` is false (default)**, it calls `internalAdapter.createUser({ ...additionalFields, email, emailVerified: true, name: name || "", image }, { method: "email-otp" })`, creates a session and returns it. With `disableSignUp: true`, it throws `INVALID_OTP` instead (and `send-verification-otp` silently sends nothing for an unknown email).
- **`name`** is passed in the *verify* call (`/sign-in/email-otp`), not the send call. It is **only used when the account is created**; for an existing user it is ignored (no profile overwrite). Missing `name` → stored as `""`. Additional fields declared in `user.additionalFields` with `input: true` are accepted the same way (`parseUserInput(..., "create")`).
- Docs, "Sign In with OTP": *"If the user is not registered, they'll be automatically registered. … To prevent automatic sign-up, pass `disableSignUp` as `true`."*
- The response does **not** carry an explicit "new user" flag: `{ token, user }` is the same shape for both cases. `user.createdAt` is in the output, and `databaseHooks.user.create.after` fires on creation (server side).

### Account enumeration

`send-verification-otp` always returns `{ success: true }`. For `type: "sign-in"` with sign-up enabled it sends the code whether or not the account exists. For the other types (and for `sign-in` with `disableSignUp`), an unknown email gets no email and the stored code is deleted, but the response is the same.

## 2. Bearer token on iOS (`set-auth-token`)

- The `bearer` plugin's `after` hook matches **every** path (`matcher() { return true }`) and, whenever the response sets a non-empty session cookie, copies its value into a `set-auth-token` header and adds it to `Access-Control-Expose-Headers` (`dist/plugins/bearer/index.mjs`).
- `signInEmailOTP` calls `setSessionCookie(ctx, { session, user })` in both the create and existing-user branches, so **`POST /api/auth/sign-in/email-otp` returns `set-auth-token` exactly like `/sign-in/email` and `/sign-in/social` today**. `APIAuthRepository.performAuthRequest` can be reused as is: its `UserResponse { user }` decoder ignores the extra `token` key.
- The body's `token` is the raw session token; the header carries the signed cookie value (`token.signature`). The bearer `before` hook accepts both (it signs an unsigned token itself unless `requireSignature: true`).
- `send-verification-otp` (like `sign-up/email`) uses `formCsrfMiddleware`. With no `Cookie`, no `Sec-Fetch-*` and no `Origin`/`Referer` headers (a native `URLSession` call), the check is skipped (`dist/api/middlewares/origin-check.mjs`, `validateFormCsrf`): the same conditions under which iOS already calls `/sign-up/email`.

## 3. Code properties and the send callback

Defaults from `dist/plugins/email-otp/index.mjs` and `types.d.mts`, confirmed by the docs "Options" section:

| Property | Default | Option | Behaviour (source) |
|---|---|---|---|
| Length | **6 digits** (`generateRandomString(len, "0-9")`) | `otpLength`, or `generateOTP({ email, type }, ctx)` | — |
| Expiry | **300 s (5 min)** | `expiresIn` (seconds) | Expired code → `OTP_EXPIRED` (400) and deleted |
| Attempts | **3** per code | `allowedAttempts` | Each wrong code → `INVALID_OTP` (400) and counter +1 (stored as `"<otp>:<attempts>"`); at the limit → `TOO_MANY_ATTEMPTS` (403), user must request a new code (`atomicVerifyOTP` in `routes.mjs`) |
| Single use | yes | — | Code is consumed atomically (`consumeVerificationValue`, Redis `GETDEL` via our `getAndDelete`) before comparison; re-written with +1 on a wrong guess |
| Resend | **`"rotate"`**: each send generates a new code, replacing the previous one (attempt counter restarts at 0) | `resendStrategy: "reuse"` resends the same code and extends its expiry; falls back to rotate when the code is hashed or the attempts are exhausted | `resolveOTP`, `tryReuseOTP` |
| Minimum delay before resending | **none in the plugin**: only the per-IP rate limit (§6) throttles sends | — | — |
| At-rest format | **`"plain"`** | `storeOTP: "hashed" \| "encrypted" \| { hash } \| { encrypt, decrypt }` | `otp-token.mjs`; comparisons use `constantTimeEqual` |

### Storage with our config

`create-auth-instance.ts` sets `secondaryStorage` (Redis) and does **not** set `verification.storeInDatabase`. In that case `internalAdapter.createVerificationValue` writes **only to Redis**, key `verification:<type>-otp-<email>` (e.g. `verification:sign-in-otp-jane@x.com`), TTL = `expiresIn`; the `verification` table is not touched (`dist/db/internal-adapter.mjs`, `createVerificationValue` / `findVerificationValue` / `consumeVerificationValue`). With the default `storeOTP: "plain"`, the code is readable in Redis.

### Send callback (to wire to Resend)

```ts
sendVerificationOTP: (
  data: { email: string; otp: string; type: "sign-in" | "email-verification" | "forget-password" | "change-email" },
  ctx?: GenericEndpointContext,
) => Promise<void>
```

- Required: without it, `send-verification-otp` throws 400 *"send email verification is not implemented"*.
- It runs through `ctx.context.runInBackgroundOrAwait(...)`. The type doc recommends not awaiting the send, to avoid timing attacks. `NotificationsService.sendAuthEmail` already never throws (ADR-023).
- No `user` object is passed (unlike `sendResetPassword` / `twoFactor.sendOTP`): only `email`, so an idempotency key would be built from `email` + `type` + `otp`, not from `user.id`.

## 4. Coexistence with the existing config

### `emailAndPassword`

- `emailOTP` does not depend on `emailAndPassword`; both can be enabled together.
- `emailAndPassword.enabled: false` makes `/sign-in/email` throw `EMAIL_PASSWORD_DISABLED` and `/sign-up/email` throw `EMAIL_PASSWORD_SIGN_UP_DISABLED` (`dist/api/routes/sign-in.mjs`, `sign-up.mjs`).
- **The admin backoffice signs in with email + password**: `apps/admin/src/app/(auth)/login/page.tsx` calls `authClient.signIn.email({ email, password })`. Turning `emailAndPassword` off entirely would break backoffice sign-in.
- **The `twoFactor` plugin only intercepts `/sign-in/email`, `/sign-in/username` and `/sign-in/phone-number`** (`dist/plugins/two-factor/index.mjs`, after-hook matcher). Admin 2FA (password, then email OTP or TOTP) therefore only exists on the email+password route.
- A narrower switch exists: **`emailAndPassword.disableSignUp: true`** closes `/sign-up/email` while keeping `/sign-in/email` (and so admin sign-in with 2FA) working (`sign-up.mjs` line `!enabled || disableSignUp`).

Options this opens (not decided here): (a) keep `emailAndPassword` fully on next to `emailOTP`; (b) keep it on with `disableSignUp: true` so only existing/admin accounts use passwords; (c) turn it off and give admins another way in, which means rethinking ADR-022 §5.

### Admin 2FA bypass via the new route (security fact)

- `/sign-in/email-otp` is **not** covered by the `twoFactor` hook. An admin whose email is known can get a full session with the emailed code alone.
- `AdminGuard` (`apps/api/src/auth/admin.guard.ts`) checks only `user.role === "admin"` and `user.twoFactorEnabled` (a user flag, not a per-session "2FA passed" proof), so **that session passes `/v1/admin/*`**.
- This is the **same situation that already exists with `/sign-in/social`** (Google), which twoFactor does not intercept either.
- Mitigations exist in Better Auth/Nest (e.g. a `hooks.before` rejecting `/sign-in/email-otp` for admin emails, a `databaseHooks.session.create.before` check, or checking the session's sign-in method in `AdminGuard`), but choosing one is a design decision.

### `emailVerification` and `emailVerified`

- **OTP sign-in sets `emailVerified: true`**: on creation directly, and for an existing unverified user through `revokeUnprovenAccountAccess` (see §5).
- `emailVerification.sendOnSignUp` is only triggered by `/sign-up/email` (`sign-up.mjs`) and OAuth registration of an unverified email (`link-account.mjs`). Creation through `/sign-in/email-otp` sends **no** verification link.
- `emailOTP.overrideDefaultEmailVerification: true` replaces the link email (`emailVerification.sendVerificationEmail`) with a `type: "email-verification"` code. `emailOTP.sendVerificationOnSignUp` sends a code after any `/sign-up*` route. Both are off by default and only matter while password sign-up remains.

### `twoFactor` email OTP

- Independent namespaces: twoFactor stores `2fa-otp-<key>` and uses its own `otpOptions.sendOTP` and `period: 5` (minutes); emailOTP stores `<type>-otp-<email>` and uses `sendVerificationOTP` and `expiresIn` (seconds). No collision, no shared code (`dist/plugins/two-factor/otp/index.mjs`).
- Two separate templates/callbacks will coexist (admin OTP email vs sign-in code email).

## 5. Account linking with Google

### Google first, then email OTP (same email)

- `/sign-in/email-otp` finds the user by email. If `emailVerified` is true (Google sets it from the ID token's `email_verified` claim, `@better-auth/core` `social-providers/google.mjs`), it **just creates a session for that user**. No `account` row is added for email-OTP: the plugin uses no `account` entry.
- Result: the Google user can sign in by code with no extra setup; `name` sent in the request is ignored.

### Pre-existing **unverified** account, then email OTP

`revokeUnprovenAccountAccess` (`dist/db/revoke-unproven-account-access.mjs`) runs: it **deletes every `account` row** (credential/password **and** OAuth links), **revokes every session**, then sets `emailVerified: true`. The docs only mention the password (*"any existing password on that account is removed and its sessions are revoked"*), but the 1.7.6 source deletes all linked accounts. Today this concerns email+password users who never clicked their verification link.

### Email OTP first, then Google (same email)

`/sign-in/social` (idToken branch) → `handleOAuthUserInfo` (`dist/oauth2/link-account.mjs`). The user exists without a Google account, so implicit linking runs only if **all** of these hold:

- the provider is trusted **or** Google says `email_verified: true`. `trustedProviders` defaults to `[]` (`dist/context/helpers.mjs`), so in our config it depends on the Google claim (true for Gmail and verified Workspace addresses);
- the local user has `emailVerified: true` (`requireLocalEmailVerified` defaults to `true`). Always true for OTP-created users;
- `accountLinking.enabled !== false` and `disableImplicitLinking !== true` (neither set in our config).

→ **Google is linked to the OTP account automatically and a session is returned.** Otherwise the route returns the `"account not linked"` error.

Net effect with the current config: the email is the identity. Google and email-OTP sign-ins with the same address land on the **same user** in both orders. That matches the map's rule "Google sur un compte existant connecte… sans écraser le profil". When linking, `applyUpdateUserInfoOnLink` may update user info from Google only if `accountLinking.updateUserInfoOnLink` is enabled (off by default).

## 6. Rate limiting with Redis secondary storage

From `dist/api/rate-limiter/index.mjs` and the plugin's `rateLimit` array:

- **Key = client IP + path** (`createRateLimitKey(ip, path)`), stored through our `secondaryStorage.increment` (`INCR` + `EXPIRE NX`, fixed window). Limits are **not per email**.
- Rule precedence: core defaults → **plugin rules** → `rateLimit.customRules` (last match wins). Custom keys are matched without the `/api/auth` prefix (already noted in `create-auth-instance.ts`).
- Defaults that apply once `emailOTP` is added:

| Path | Core default | `emailOTP` rule (wins) |
|---|---|---|
| `/email-otp/send-verification-otp` | 3 / 60 s | **3 / 60 s** |
| `/sign-in/email-otp` | 3 / 10 s (all `/sign-in*`) | **3 / 60 s** |
| `/email-otp/check-verification-otp`, `/email-otp/verify-email`, reset/change routes | — | **3 / 60 s** |

  `emailOTP({ rateLimit: { window, max } })` changes **all** of these at once; `customRules["/sign-in/email-otp"]` etc. override per path.
- Brute-force bound per code: `allowedAttempts` (3) wrong codes invalidate it, and each new code requires a send (3 per minute per IP). The per-code success odds of a blind guess are 3 / 10⁶ with the defaults.
- On 429 the response carries `X-Retry-After` (seconds). `APIAuthRepository.mapError` already maps 429 to `.rateLimited`.
- Sends cost a Resend email each. Nothing in the plugin caps sends **per address** (an attacker rotating IPs can trigger repeated emails to one address). Per-email throttling would be custom (`hooks.before` on the send path, or a `customRules` function).

## 7. Error codes the iOS client would meet

| Code | HTTP | When |
|---|---|---|
| `INVALID_OTP` | 400 | wrong code, no code stored, or (with `disableSignUp`) unknown email |
| `OTP_EXPIRED` | 400 | code past `expiresIn` |
| `TOO_MANY_ATTEMPTS` | 403 | attempts exhausted; a new code must be requested |
| `INVALID_EMAIL` | 400 | malformed email on send |
| (no code, message only) | 429 | rate limit |

`APIAuthRepository.mapError` maps 403 to the generic `.server(message:)` branch today (only 401 maps to `.invalidCredentials`).

## Summary of facts that bear on the map (#105)

1. Two calls: `POST /api/auth/email-otp/send-verification-otp {email, type:"sign-in"}`, then `POST /api/auth/sign-in/email-otp {email, otp, name?}`. The second call **creates the account on first use** (default) and returns `set-auth-token` like today's routes.
2. 6 digits, 5 min, 3 attempts, new code on each resend; no built-in resend delay beyond per-IP rate limits (3/min). Stored only in Redis, in plain text by default.
3. "No password" for the app does not require disabling `emailAndPassword`. Disabling it **breaks admin backoffice sign-in and the twoFactor flow**, which only hook `/sign-in/email`; `emailAndPassword.disableSignUp` is the narrower switch.
4. `/sign-in/email-otp` is not covered by admin 2FA, the same gap as Google sign-in today.
5. Same email ⇒ same user across Google and email OTP, in both orders, with the current defaults. Exception: a pre-existing **unverified** account loses all its linked accounts and sessions on first OTP sign-in.
