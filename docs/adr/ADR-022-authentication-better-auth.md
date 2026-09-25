# ADR-022: Authentication — Better Auth configuration, providers, sessions and admin role

- **Status**: accepted
- **Date**: 2026-09-25
- **Deciders**: echimine
- **Tags**: auth, better-auth, security, mobile, backoffice

## Context

ADR-003 chose Better Auth as the authentication library, mounted on `/api/auth/*` in the `api` app (ADR-009), and already noted two open points: Better Auth has no *first-party* NestJS integration (the NestJS integration is community-maintained, `@thallesp/nestjs-better-auth`) and no iOS SDK, and iOS session storage was left as "tokens managed on the Swift side (Keychain)". ADR-013 assumed a **session cookie** for the backoffice, kept on the backoffice domain through the Next.js proxy. ADR-017 fixed the `user` table as the Better Auth schema plus a `role` column (`user` | `admin`), plus `session`, `account`, `verification` (module `auth`, `public` schema).

What was still undecided, and that this ADR settles, is needed for account creation, login/register and the admin role to actually be implementable:
- which sign-in methods are offered (email/password, and which OAuth providers);
- how the **same** Better Auth instance serves two very different clients — a native iOS app that cannot rely on cookies, and a Next.js backoffice that can — without duplicating the auth backend;
- how the backoffice cookie is scoped, given that a second web app (not iOS) is expected to sit on another subdomain of the same domain later and should not require reconfiguring auth;
- how the `admin` role from ADR-017 is actually enforced and exposed.

This decision is scoped to account creation, session handling and the minimum second-factor requirement for the admin role (§5). It does not cover authorization rules for specific business endpoints beyond the admin guard already described in ADR-009/ADR-013.

## Decision

### 1. Sign-in methods

Three ways to create an account / sign in, all on the same Better Auth instance:

```ts
export const auth = betterAuth({
  emailAndPassword: {
    enabled: true,
  },
  socialProviders: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    },
    apple: {
      clientId: process.env.APPLE_CLIENT_ID!,       // Services ID
      clientSecret: process.env.APPLE_CLIENT_SECRET!, // generated JWT (private key + Team ID + Key ID)
      appBundleIdentifier: process.env.APPLE_APP_BUNDLE_ID!, // native Sign in with Apple on iOS
    },
  },
});
```

- **Apple is mandatory**, not optional: an iOS app that offers any third-party sign-in (Google) must also offer Sign in with Apple (App Store Review Guideline 4.8). `appBundleIdentifier` is required for the native flow (`ASAuthorizationController` on iOS) in addition to the web Services ID flow.
- Email/password uses Better Auth's built-in account-enumeration protections (generic error messages, dummy operations on invalid requests) — no custom work needed there.
- Email verification (`emailVerification.sendOnSignUp`) and password reset (`emailAndPassword.sendResetPassword`) need a transactional email sender; the sender itself (provider, templates) is not decided here and can be a follow-up ADR or an implementation detail — this ADR only requires that both handlers are defined before going to production, since Better Auth no-ops silently otherwise. *Amended by [ADR-023](ADR-023-transactional-email-resend.md)*: Resend, on a dedicated `mail.strava.echimine.fr` subdomain, with React Email templates.

### 2. Two session transports on one backend: cookie for web, bearer token for mobile

Better Auth supports both from the same instance; the client decides which one it uses per request, so there is no need for two Better Auth instances or two backends.

The NestJS binding used to expose this instance to the `api` app is `@thallesp/nestjs-better-auth` (`AuthModule.forRoot({ auth })`, global `AuthGuard`, `@Session()` decorator, `@AllowAnonymous()`/`@OptionalAuth()` for the routes that need to opt out) — community-maintained, not a Better Auth core package, which is why ADR-003 flagged it as "no official NestJS integration" rather than "no NestJS integration at all".

```ts
import { betterAuth } from "better-auth";
import { bearer } from "better-auth/plugins/bearer";
import { admin } from "better-auth/plugins/admin";
import { twoFactor } from "better-auth/plugins/two-factor";

export const auth = betterAuth({
  // ...emailAndPassword, socialProviders as above
  plugins: [
    bearer(),      // §2a — mobile
    admin(),       // §3 — admin role
    twoFactor({    // §5 — admin-only 2FA, TOTP or email OTP (admin's choice)
      issuer: "Clone Strava",
      otpOptions: {
        sendOTP: async ({ user, otp }) => sendAdminOtpEmail(user.email, otp),
        period: 5,
      },
      // totpOptions: defaults are used (digits: 6, period: 30)
    }),
  ],
  trustedOrigins: [
    "https://admin.strava.echimine.fr",
    "app://strava",                 // iOS custom scheme, for OAuth redirects
  ],
  advanced: {
    crossSubDomainCookies: {        // §2b — backoffice (and future web apps)
      enabled: true,
      domain: ".strava.echimine.fr",
    },
    useSecureCookies: true,
  },
});
```

**a. Mobile (iOS, Swift): bearer token, no cookie.**
The `bearer` plugin lets a signed-in client trade its session for an opaque bearer token, sent as `Authorization: Bearer <token>` instead of relying on a `Set-Cookie`/`Cookie` round-trip that a native app does not do transparently like a browser. The API validates that header on every request the same way it validates the cookie for web clients — Better Auth exposes both under the same session-resolution call, so NestJS guards do not branch on client type. The token is stored in the iOS **Keychain** (confirms ADR-003), never in `UserDefaults` or on disk unencrypted.

**b. Admin backoffice (Next.js): session cookie, scoped to `.strava.echimine.fr`.**
`crossSubDomainCookies.enabled` with a leading-dot `domain` makes the session cookie valid across every subdomain of `strava.echimine.fr`, not just `admin.strava.echimine.fr`. This keeps ADR-013's design (cookie handled by the Next.js proxy, never exposed to `fetch` in application code) and additionally means that **a future web app on another subdomain** (e.g. a companion webapp, `app.strava.echimine.fr`) shares the same signed-in session without any change to this configuration — the reason this was raised for this ADR. Cookies keep Better Auth's secure defaults: `secure: true`, `httpOnly: true`, `sameSite: "lax"`, `__Secure-` prefix.
Consequence: **only** subdomains of `strava.echimine.fr` should ever be trusted with this cookie — never a fully different domain, and never a subdomain outside our control.

**c. `trustedOrigins`.**
Both the backoffice origin and the iOS app's custom URL scheme (for the OAuth redirect back into the app) must be listed, or Better Auth's origin/redirect validation (`callbackURL`, `redirectTo`, `errorCallbackURL`) rejects the request with `403`. `disableCSRFCheck` / `disableOriginCheck` stay at their default (`false`, i.e. checks stay on) — mobile does not need them disabled since it authenticates via bearer token, not a cookie subject to CSRF.

### 3. Admin role

The `admin` plugin operates on the `role` column ADR-017 already added to `user`, so no schema change is needed here. It provides:
- server-side helpers to grant/revoke the role and to ban/unban a user, callable from a seed script or from a future backoffice "manage admins" screen;
- an `impersonateUser` capability the backoffice does **not** enable (not needed, avoids audit complexity).

The actual authorization boundary is unchanged from ADR-009/ADR-013: every admin endpoint checks `role === "admin"` in a NestJS guard reading the resolved session (cookie or bearer, per §2), and `GET /v1/me` returns that role so the backoffice `(admin)` layout can show "access denied" without a network round-trip on every navigation. The `admin` plugin is what makes the role a first-class Better Auth concept (typed on the session/user object) instead of an ad hoc column the guard reads blindly.

### 4. Rate limiting on auth endpoints

Production default (`rateLimit.enabled: true`) is kept, with tighter custom rules on the endpoints that matter most for brute-forcing an account:

```ts
rateLimit: {
  enabled: true,
  storage: "secondary-storage", // Redis (ADR-003)
  customRules: {
    "/api/auth/sign-in/email": { window: 60, max: 5 },
    "/api/auth/sign-up/email": { window: 60, max: 3 },
  },
},
```

`storage: "secondary-storage"` reuses the Redis instance already required by ADR-003/ADR-010/ADR-011, instead of adding a new stateful dependency.

### 5. Second factor, admins only, credential sign-in only — email OTP or authenticator app, admin's choice

Rather than skipping 2FA entirely at launch, or forcing it on every user, **admin accounts must verify a second factor, and only when they sign in with email/password.** This is a property of Better Auth's `twoFactor` plugin itself, not a workaround: *"2FA can only be enabled for credential (email/password) accounts"* — a Google or Apple sign-in never goes through the credential flow, so it is never asked for the second factor. That lines up with the actual goal: OAuth sign-in already carries whatever authentication strength Google/Apple enforced on their side, so the second factor is only useful — and only offered — where our own password is the sole line of defense.

**Both of the `twoFactor` plugin's built-in methods are enabled, and each admin picks one at setup time** — this is not two parallel features to build, `twoFactor` supports both from the same config:
- **Email OTP** (`otpOptions.sendOTP`): no app to install, one code per sign-in, mailed the same way the password-reset email already is.
- **TOTP / authenticator app** (`totpOptions`, the default flow): `authClient.twoFactor.enable()` returns a `totpURI` to scan into any standard authenticator (Google Authenticator, Authy, 1Password…), verified fully offline — no dependency on outbound email at sign-in time.

Choosing TOTP removes the "admin 2FA depends on outbound email deliverability" failure mode entirely for that admin: sign-in no longer needs a mail to go out at all. An admin who prefers email OTP over installing an authenticator app can still do so — the trade-off (§ Consequences) is theirs to make, not imposed by this ADR. Backup codes (`backupCodeOptions`, generated for either method) remain the recovery path if a phone or inbox is unavailable.

Mechanics:
- Better Auth does not have a "require 2FA for this role" primitive; enforcement is application-level: a `databaseHooks.user.update.after` hook detects a promotion to `role: "admin"` (via the `admin` plugin, §3) and marks the account as requiring 2FA setup (either method), and the NestJS admin guard refuses backoffice access until `twoFactorEnabled` is `true` for that user — mirroring how the role check itself already works (§3).
- Regular (non-admin) users are never prompted; this keeps the mobile sign-up flow unchanged.
- `otpOptions.storeOTP: "hashed"` (the code is single-use and short-lived, no need to keep it recoverable) and the default `allowedAttempts`/rate limiting (§4) apply to the email path; TOTP secrets are encrypted with the auth secret by default.

### 6. Secrets

`BETTER_AUTH_SECRET` (32+ bytes, `openssl rand -base64 32`), Google and Apple OAuth credentials all go through environment variables, never committed — consistent with this project's existing rule (`CLAUDE.md`: never commit secrets or `.env` files) and with ADR-020's rule 5 for MCP secrets.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **One Better Auth instance for web, a separate hand-rolled token service for mobile** | Full control over the mobile token format | Two auth systems to maintain and secure, duplicated user/session logic | Rejected |
| **Cookie-based session for mobile too** (`skipStateCookieCheck`-style workaround) | Same transport everywhere | Native iOS `URLSession` does not manage cookie jars the way a browser does; fragile, fights the platform | Rejected |
| **Cookie scoped only to `admin.strava.echimine.fr`** | Slightly narrower blast radius | Any future subdomain app needs its own reconfiguration and effectively its own session; defeats the point of a shared domain | Rejected |
| **`role` enforced only in application code, no `admin` plugin** | No new plugin | Role management (grant/revoke, ban) reimplemented by hand; role not typed on the session object | Rejected |
| **2FA required for every user, every provider** | Simpler rule ("2FA is on") | Not enforceable on OAuth sign-in anyway (Better Auth only supports 2FA on credential accounts), and pointless friction for mobile users who already went through Google/Apple's own auth | Rejected |
| **No 2FA at all at launch** | Nothing to build | Leaves the admin role — the highest-value target — protected by a password alone | Rejected in favor of §5 |
| **Only email OTP for admins, no TOTP option** | Nothing to install, reuses the transactional-email path (§1) already needed for verification/reset | Single point of failure on outbound email deliverability, exactly the risk flagged below | Rejected — TOTP offered alongside it (§5) |
| **Only TOTP for admins, no email OTP option** | No dependency on outbound email at sign-in | Forces every admin to install an authenticator app even if they'd rather not; no reason to remove a method Better Auth already supports | Rejected — email OTP offered alongside it (§5) |
| **Auth0 / Clerk (SaaS)** | Less to configure | Already rejected in ADR-003 (data outside our database, SaaS dependency) | Rejected |

## Consequences

### Positive
- One Better Auth instance and one set of business rules serve both iOS and the backoffice; no duplicated session logic.
- The Keychain/bearer-token approach for iOS resolves the open point ADR-003 left unaddressed.
- The cross-subdomain cookie means a future web app on `*.strava.echimine.fr` gets authentication "for free".
- Rate limiting on `sign-in`/`sign-up` and Better Auth's built-in enumeration protections raise the bar against credential-stuffing and brute force without custom code.
- The admin role — the highest-value target — gets a second factor without adding any friction for mobile/OAuth users.
- Offering both TOTP and email OTP means an outage of the transactional sender (§1) doesn't lock out an admin who chose TOTP; each admin picks the trade-off that suits them.

### Negative / Risks
- **Bearer tokens do not expire on their own the way a short-lived JWT would** unless `session.expiresIn`/`updateAge` are tuned; a stolen Keychain token is valid until the session it maps to ends. Mitigated by keeping the token in the Keychain (not backed up in plaintext) and by the ability to `revokeSession`/`revokeSessions` server-side.
- **`crossSubDomainCookies` trusts every subdomain of `strava.echimine.fr`** with the session; any future subdomain (e.g. a staging or demo app) must be treated as a trusted first-party surface, or moved to a separate domain instead.
- **Apple OAuth setup has real operational cost**: Services ID, private key, Team ID, Key ID to generate the client secret JWT, and it must be regenerated periodically (Apple-signed secrets expire) — an operational task to track (VPS/CI secrets rotation), not just a one-time config.
- **An admin who chooses email OTP still depends on outbound email deliverability** for that admin's sign-in: if the transactional email sender (§1) is down or delayed, they are locked out of the backoffice along with everyone waiting on a verification/reset email. Mitigated in two ways: TOTP is offered as a deliverability-independent alternative (§5), and *[ADR-023](ADR-023-transactional-email-resend.md)*'s bounce/complaint webhook flags a broken inbox instead of failing silently. Backup codes are generated for both methods but no explicit recovery UX/runbook is defined yet for "an admin lost their phone and their inbox is also down" — a follow-up, not a blocker.
- **The "require 2FA for admins" rule is enforced in application code, not by Better Auth itself** (§5): a bug in the `databaseHooks`/guard logic could let a freshly promoted admin in before 2FA is actually set up. Needs a test covering the promotion → guard-blocks-until-verified path.

## References
- Better Auth: https://better-auth.com/docs
- Better Auth plugins reference: `bearer`, `admin`, `two-factor` — https://better-auth.com/docs/plugins
- Better Auth NestJS integration (community-maintained): https://better-auth.com/docs/integrations/nestjs, https://github.com/ThallesP/nestjs-better-auth
- Sign in with Apple (native, iOS): App Store Review Guideline 4.8
- [ADR-003: Backend stack and architecture](ADR-003-backend.md)
- [ADR-009: Backend API](ADR-009-backend-api.md)
- [ADR-013: Backoffice architecture](ADR-013-backoffice-architecture.md)
- [ADR-017: Data model](ADR-017-data-model.md)
- [ADR-020: MCP servers](ADR-020-mcp-servers.md)

## Links

- **Depends on**: [ADR-003](ADR-003-backend.md), [ADR-009](ADR-009-backend-api.md), [ADR-013](ADR-013-backoffice-architecture.md), [ADR-017](ADR-017-data-model.md)
- **Amends**: [ADR-003](ADR-003-backend.md) (resolves the "tokens managed on the Swift side" open point), [ADR-013](ADR-013-backoffice-architecture.md) (cookie scope)
- **Amended by**: [ADR-023](ADR-023-transactional-email-resend.md) (transactional email sender for verification, password reset, admin OTP)
