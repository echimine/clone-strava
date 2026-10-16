import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { admin, bearer, twoFactor } from "better-auth/plugins";
import { schema, type Database } from "@repo/db";
import {
  NotificationsService,
  renderAdminOtpEmail,
  renderResetPasswordEmail,
  renderVerifyEmail,
} from "../notifications/index.js";
import type { Redis } from "../infrastructure/index.js";
import { createAuthSecondaryStorage } from "./auth-secondary-storage.js";
import type { AuthModuleOptions } from "./auth.constants.js";

/**
 * Builds the Better Auth instance (ADR-021 §1, ADR-009 §3): `drizzleAdapter`
 * on the shared `DATABASE` connection, the `admin` plugin (role-based
 * backoffice guard, ADR-009 §3 "an admin role guard protects the
 * backoffice endpoints") and the `bearer` plugin (iOS `Authorization:
 * Bearer <token>` sessions).
 *
 * Factored out of `AuthModule` so its return type — with the plugins'
 * augmentations (e.g. `admin()`'s `user.role`) — can be reused as the
 * `AUTH_INSTANCE` type in `auth.service.ts` without losing that
 * augmentation to a generic `ReturnType<typeof betterAuth>`.
 */
export function createAuthInstance(
  db: Database,
  redis: Redis,
  notifications: NotificationsService,
  options: AuthModuleOptions,
) {
  return betterAuth({
    // The full `@repo/db` schema is passed (not just the four auth
    // tables): the adapter only looks up the models it needs by name, and
    // every table uses Better Auth's default model names (ADR-021 §7
    // "kept exactly as in the Better Auth documentation").
    database: drizzleAdapter(db, { provider: "pg", schema }),
    secret: options.secret,
    baseURL: options.baseUrl,
    trustedOrigins: options.trustedOrigins,
    // ADR-022 §4: session/verification cache and rate-limit counters live
    // in Redis, not in-process memory (the API runs as several instances).
    secondaryStorage: createAuthSecondaryStorage(redis),
    rateLimit: {
      enabled: true,
      storage: "secondary-storage",
      // Verified against the installed `better-auth@1.7.6` source
      // (`dist/api/rate-limiter/index.mjs`): custom rule keys are matched
      // against the path with no `/api/auth` prefix, unlike ADR-022 §4's
      // own snippet.
      customRules: {
        "/sign-in/email": { window: 60, max: 5 },
        "/sign-up/email": { window: 60, max: 3 },
      },
    },
    emailAndPassword: {
      enabled: true,
      // ADR-022/ADR-023: sent through the `notifications` platform module
      // (Resend), never throws (logs only) per NotificationsService's own
      // contract.
      sendResetPassword: async ({ user, url }) => {
        const html = await renderResetPasswordEmail({ url, logoUrl: options.emailLogoUrl });
        await notifications.sendAuthEmail({
          to: user.email,
          subject: "Reset your password",
          html,
          idempotencyKey: `reset-password/${user.id}`,
        });
      },
    },
    // ADR-022 §3: verification email sent on sign-up, same
    // `notifications`/React Email pipeline as password reset.
    emailVerification: {
      sendOnSignUp: true,
      sendVerificationEmail: async ({ user, url }) => {
        const html = await renderVerifyEmail({ url, logoUrl: options.emailLogoUrl });
        await notifications.sendAuthEmail({
          to: user.email,
          subject: "Verify your email",
          html,
          idempotencyKey: `verify-email/${user.id}`,
        });
      },
    },
    // ADR-022: Google only — Apple Sign-In is deferred (blocked on the
    // Apple Developer Program), not even stubbed here.
    socialProviders: {
      google: {
        clientId: options.googleClientId,
        clientSecret: options.googleClientSecret,
      },
    },
    advanced: {
      // ADR-017: identifiers are `uuid`, not Better Auth's default text id.
      database: { generateId: "uuid" },
      // ADR-022: the backoffice lives on a subdomain of strava.echimine.fr;
      // the session cookie must be readable there too.
      crossSubDomainCookies: { enabled: true, domain: ".strava.echimine.fr" },
      useSecureCookies: true,
      // Rate limiting keys on the client IP. In production Traefik drops any
      // client-supplied X-Forwarded-For (untrusted source) and sets its own,
      // single-value header, which Better Auth trusts without `trustedProxies`.
      // Locally there is no proxy: Better Auth falls back to 127.0.0.1 only
      // when NODE_ENV=development (set by the api `dev` script).
      ipAddress: { ipAddressHeaders: ["x-forwarded-for"] },
    },
    plugins: [
      admin(),
      bearer(),
      // ADR-022 §5: 2FA mandatory for admins. Adds `user.twoFactorEnabled`,
      // checked directly by `AdminGuard` — no separate "2FA required" flag.
      twoFactor({
        issuer: "Nervo",
        otpOptions: {
          period: 5,
          sendOTP: async ({ user, otp }) => {
            const html = await renderAdminOtpEmail({ otp, email: user.email, logoUrl: options.emailLogoUrl });
            await notifications.sendAuthEmail({
              to: user.email,
              subject: "Your admin verification code",
              html,
              idempotencyKey: `admin-otp/${user.id}-${otp}`,
            });
          },
        },
      }),
    ],
    // ADR-022 §5: extension point for a future audit log of admin
    // `twoFactorEnabled` changes — no separate flag needed, so left as a
    // documented no-op for now.
    databaseHooks: {
      user: {
        update: {
          after: async () => {
            // Intentionally empty (see comment above).
          },
        },
      },
    },
  });
}
