# ADR-023: Transactional email with Resend

- **Status**: accepted
- **Date**: 2026-09-25
- **Deciders**: echimine
- **Tags**: email, resend, deliverability, auth

## Context

ADR-022 fixed three points in the authentication flow that each need to send an email, and explicitly left the sender as "not decided here... can be a follow-up ADR":
- `emailVerification.sendVerificationEmail` — verify a new email/password account;
- `emailAndPassword.sendResetPassword` — password reset;
- `twoFactor.otpOptions.sendOTP` — the admin-only, credential-only OTP second factor.

All three are handlers Better Auth calls with `(user, url/otp, request)` and leaves entirely to the app to implement — Better Auth does not send email itself. This ADR picks the sender behind those three handlers and the minimum deliverability setup so they actually land in the inbox instead of being silently dropped or spam-filtered, which is a real risk in particular for the OTP admin flow (ADR-022 already flagged "admin 2FA depends on outbound email deliverability" as a risk).

This ADR is scoped to transactional email triggered by the backend (`packages/core`, `auth` module). It does not cover marketing email, newsletters, or user-facing product notifications unrelated to auth — those would reuse the same Resend account but are a separate concern (Resend Broadcasts/Contacts, not in scope here).

## Decision

### 1. Resend as the transactional email provider

**Resend** (`resend` npm package, Node SDK) sends the three emails above from the `worker` or `api` app — send calls are cheap and don't need a job, but are still routed through a thin `packages/core` `notifications` platform module (same pattern as `analytics`/`storage` in ADR-021: wraps an external service, owns no table, no business rule) so `auth`, `worker` and any future module calling it never talk to the Resend SDK directly.

```ts
import { Resend } from "resend";

const resend = new Resend(process.env.RESEND_API_KEY);

export async function sendAuthEmail(params: {
  to: string;
  subject: string;
  html: string;
  idempotencyKey: string; // "<event-type>/<user-id>", e.g. "verify-email/usr_123"
}) {
  const { error } = await resend.emails.send(
    {
      from: "Clone Strava <noreply@mail.strava.echimine.fr>", // Amended by ADR-032 §1: "Nervo <noreply@mail.strava.echimine.fr>"
      to: params.to,
      subject: params.subject,
      html: params.html,
    },
    { idempotencyKey: params.idempotencyKey },
  );
  if (error) {
    // logged + surfaced (§4), never thrown — the SDK never throws for API-level errors
  }
}
```

*Amended by [ADR-032](ADR-032-brand-and-motion-design.md) §1*: the sender name is Nervo, `from: "Nervo <noreply@mail.strava.echimine.fr>"`; the address keeps "strava" until the domains are renamed.

Wired into the three Better Auth handlers from ADR-022:

```ts
export const auth = betterAuth({
  emailVerification: {
    sendOnSignUp: true,
    sendVerificationEmail: ({ user, url }) =>
      sendAuthEmail({
        to: user.email,
        subject: "Verify your email",
        html: renderVerifyEmail({ url }),               // React Email, §2
        idempotencyKey: `verify-email/${user.id}`,
      }),
  },
  emailAndPassword: {
    enabled: true,
    sendResetPassword: ({ user, url }) =>
      sendAuthEmail({
        to: user.email,
        subject: "Reset your password",
        html: renderResetPasswordEmail({ url }),
        idempotencyKey: `reset-password/${user.id}`,
      }),
  },
  plugins: [
    twoFactor({
      otpOptions: {
        sendOTP: ({ user, otp }) =>
          sendAuthEmail({
            to: user.email,
            subject: "Your admin verification code",
            html: renderAdminOtpEmail({ otp }),
            idempotencyKey: `admin-otp/${user.id}-${otp}`, // otp itself makes each code's send unique
          }),
      },
    }),
  ],
});
```

### 2. Templates with React Email

Email bodies are React components rendered to HTML with **`@react-email/components`** (`renderVerifyEmail`, `renderResetPasswordEmail`, `renderAdminOtpEmail` above), not hand-written HTML strings or Resend's hosted template feature. Kept in `packages/core/src/notifications/emails/*.tsx`, next to the module that owns the wrapper. Reasons: these three templates are few, code-reviewed like the rest of the codebase, need real conditionals (locale, a masked email in the OTP template) that a hosted template's `{{{VAR}}}` mustache syntax handles poorly, and React Email's components already handle the accessibility basics (semantic headings, alt text slots) this project should not reinvent by hand.

### 3. Domain and authentication (SPF/DKIM/DMARC)

A **dedicated sending subdomain**, `mail.strava.echimine.fr`, is verified in Resend and used as the `from` domain — not `strava.echimine.fr` itself (shared with `api.`/`admin.`/`ws.`, ADR-018) and not the Resend sandbox (`onboarding@resend.dev`, which only delivers to the account's own address and would silently break every real signup).

- SPF, DKIM (Resend-provided selector) and DMARC TXT records added on `mail.strava.echimine.fr` through the VPS's DNS provider, alongside the existing Traefik-routed subdomains from ADR-018.
- DMARC rollout starts at `p=none` (monitor only) — this is a low-volume, all-transactional sender, so escalating to `p=quarantine`/`p=reject` can follow once a few weeks of reports confirm no legitimate mail is being flagged.
- Records verified with `dig TXT mail.strava.echimine.fr`, `dig TXT resend._domainkey.mail.strava.echimine.fr`, `dig TXT _dmarc.mail.strava.echimine.fr` before the first production send.
- No IP/domain warm-up schedule is needed at MVP volume (a handful of signups/day, admin OTP even rarer), but the same warm-up curve applies if activity email (kudos, comments) is ever added to this sender later.

### 4. Reliability: idempotency, retries, delivery tracking

- **Idempotency key** on every send, `<event-type>/<user-id>` (per the SDK's own convention), so a retried request after a timeout never double-sends a reset-password or OTP email — critical for OTP specifically, where a duplicate email with a *different* code would confuse the user mid-login.
- **No queue/BullMQ job for these three emails**: they are synchronous, user-facing, latency-sensitive (the user is looking at a "check your email" screen) API calls, unlike the job-based notifications ADR-011 already covers for asynchronous work. A failed send is logged and surfaced as a normal `5xx`/error to the caller — Better Auth's flow already lets the user retry (resend verification, resend OTP) rather than needing our own retry-with-backoff queue.
- **Resend webhook** (`email.bounced`, `email.complained`, `email.delivery_delayed`) registered against `api.strava.echimine.fr/v1/webhooks/resend`, verified with `resend.webhooks.verify()` (same secret-header pattern already used for the RevenueCat webhook, ADR-009/ADR-014). On `email.bounced` for a `user.email`, the account is flagged (`email_verified` cannot be trusted) — this is the minimum needed to notice a broken inbox rather than a full bounce/complaint-driven suppression pipeline, which is not needed at this volume.

### 5. Secrets

`RESEND_API_KEY` used by the **running app** (§1, sending the three emails) is a **sending-only** restricted key, since nothing in `packages/core` needs to manage domains/contacts/webhooks at runtime. `RESEND_WEBHOOK_SECRET` goes alongside it. Both through environment variables on the VPS (`.env`, `chmod 600`, ADR-018), never committed — same rule as ADR-020/ADR-022.

### 6. Development tooling: Resend MCP and skills

Consistent with ADR-020's rule ("always use the appropriate MCP server when one exists, rather than working from memory or reproducing by hand what the tool does"), **the Resend MCP server is the assistant's mandatory entry point** for anything Resend-related during development — not a plain `curl`/dashboard round-trip reproduced by hand:

| Need | Tool |
|---|---|
| Verify DNS / domain status, create the `mail.strava.echimine.fr` domain, inspect its SPF/DKIM/DMARC records | Resend MCP (`get-domain`, `create-domain`, `verify-domain`) |
| Register/inspect the delivery webhook (§4), replay a failed event while debugging | Resend MCP (`create-webhook`, `list-webhook-events`, `replay-webhook-event`) |
| Look up a specific send while debugging a "did the OTP email go out" question | Resend MCP (`get-email`, `list-emails`, `get-log`) |
| Manage the sending-only API key itself | Resend MCP (`create-api-key`, with the `sending`-only scope from §5) |
| Write/adjust the three email API calls, idempotency keys, retry semantics | `resend` skill (SDK gotchas: `{ data, error }` return shape, idempotency key format, sandbox-domain 403) |
| Write/preview the React Email templates (§2) | `react-email` skill |
| Diagnose deliverability (SPF/DKIM/DMARC, spam placement, bounce/complaint rates) | `email-best-practices` skill |
| One-off sends, domain/webhook/log inspection from a terminal or CI script | `resend-cli` skill (the `resend` CLI) |

This keeps domain verification, webhook wiring and template iteration reproducible and MCP-driven rather than a manually-clicked dashboard state that the next session (or the next person) can't see. It does **not** change §5: the MCP server authenticates with the assistant's own Resend session, entirely separate from the running app's `RESEND_API_KEY`, and is local/user-scoped tooling, never a versioned `.mcp.json` secret (ADR-020 rule 2).

## Alternatives Considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Nodemailer + a raw SMTP account** (e.g. the VPS's own mail relay) | No third-party dependency | No deliverability tooling (bounce/complaint webhooks, suppression list), self-managed SPF/DKIM/DMARC, VPS IP reputation not built for outbound mail | Rejected |
| **AWS SES** | Cheaper at high volume | More setup (sandbox mode lifted by support request, IAM), no benefit at this project's volume | Rejected |
| **Resend hosted templates** (dashboard-edited, `{{{VAR}}}` syntax) instead of React Email | No template code in the repo | Weaker for conditionals (locale, masked email), template edits happen outside code review, must be published before use (draft templates silently fail to send) | Rejected |
| **`from` on the bare `strava.echimine.fr` domain** | One fewer DNS subdomain to configure | Mixes transactional-email reputation with the domain also serving `api.`/`admin.`/`ws.` traffic; a spam/complaint problem on one hurts the other | Rejected |
| **BullMQ job for every auth email** (consistent with ADR-011's job-based worker pattern) | Uniform "everything async" pattern, automatic retry via BullMQ | Adds latency and failure modes to a flow where the user is actively waiting on the email; Resend's own idempotency key already prevents the duplicate-send failure mode a queue would guard against | Rejected |

## Consequences

### Positive
- Resolves the sender ADR-022 explicitly deferred; the admin OTP flow is no longer standing on an undefined `sendOTP`.
- Bounce/complaint visibility via webhook means a broken admin or user inbox is noticed instead of silently failing every future login.
- A dedicated `mail.` subdomain isolates this sender's reputation from `api.`/`admin.`/`ws.`.
- React Email templates are reviewed and tested like any other code, not edited out-of-band in a dashboard.
- Domain/webhook/log inspection goes through the Resend MCP and skills (§6), consistent with ADR-020, instead of ad hoc dashboard clicks or hand-rolled `curl` calls.

### Negative / Risks
- **New DNS + third-party dependency** on the auth-critical path: verification, password reset and admin login-with-2FA all now depend on Resend's availability and on `mail.strava.echimine.fr`'s DNS records staying correct. Add to the VPS deploy checklist (ADR-018) alongside the RevenueCat/PostHog keys already tracked as pending.
- **Sending-only API key** limits what the *running app* can do (§5) if domain/contact management is ever needed from application code itself — acceptable, since that stays MCP/dashboard-driven tooling (§6), not something the app performs at runtime.
- **No automated suppression handling** beyond flagging on bounce (§4): a user who mistypes their email at signup gets no automatic retry path yet, just an unverified account. Acceptable at MVP scale; revisit if signup volume grows.

## References
- Resend: https://resend.com/docs
- React Email: https://react.email/docs
- Resend webhooks (verification, event types): https://resend.com/docs/dashboard/webhooks/introduction
- Resend deliverability / DNS setup: https://resend.com/docs/dashboard/domains/introduction
- [ADR-009: Backend API](ADR-009-backend-api.md) (webhook pattern, secret-header auth)
- [ADR-011: Backend worker](ADR-011-backend-worker.md) (job-based vs synchronous work)
- [ADR-014: RevenueCat](ADR-014-revenuecat.md) (existing webhook precedent)
- [ADR-018: Docker/VPS deployment](ADR-018-docker-vps-deployment.md) (domain, `.env`, DNS)
- [ADR-021: Bounded contexts and module boundaries](ADR-021-bounded-contexts-and-module-boundaries.md) (platform module pattern)
- [ADR-022: Authentication — Better Auth](ADR-022-authentication-better-auth.md) (the three handlers this ADR implements)
- [ADR-020: MCP servers for the development assistant](ADR-020-mcp-servers.md) (the "always use the appropriate MCP" rule this ADR follows)

## Links

- **Depends on**: [ADR-022](ADR-022-authentication-better-auth.md)
- **Amends**: [ADR-022](ADR-022-authentication-better-auth.md) (resolves the deferred email-sender choice; mitigates its "admin 2FA depends on outbound email deliverability" risk)
- **Amended by**: [ADR-032](ADR-032-brand-and-motion-design.md) (§1 sender name, preview and heading become Nervo; §2 email header with the hosted wordmark PNG)
- **Related**: [ADR-009](ADR-009-backend-api.md), [ADR-011](ADR-011-backend-worker.md), [ADR-014](ADR-014-revenuecat.md), [ADR-018](ADR-018-docker-vps-deployment.md), [ADR-020](ADR-020-mcp-servers.md) (MCP/skills usage rule), [ADR-021](ADR-021-bounded-contexts-and-module-boundaries.md)
