import { Logger } from "@nestjs/common";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { admin, bearer, emailOTP, twoFactor } from "better-auth/plugins";
import { ANALYTICS_EVENTS } from "@repo/contracts";
import { schema, type Database } from "@repo/db";
import type { AnalyticsService } from "../analytics/index.js";
import {
  emailWordmarkUrl,
  NotificationsService,
  renderAdminOtpEmail,
  renderResetPasswordEmail,
  renderSignInCodeEmail,
  renderVerifyEmail,
} from "../notifications/index.js";
import type { Redis } from "../infrastructure/index.js";
import { createAuthSecondaryStorage } from "./auth-secondary-storage.js";
import type { AuthModuleOptions } from "./auth.constants.js";
import { sessionAuthMethodFor, signUpMethodFor } from "./domain/session-auth-method.js";

/** Dev-only addresses that get the fixed Sign-in code, without any email (ADR-035 §2). */
const DEV_FIXED_CODE_DOMAIN = "@stravaclone.test";
const DEV_FIXED_CODE = "000000";

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
  analytics: AnalyticsService,
  options: AuthModuleOptions,
) {
  const logoUrl = emailWordmarkUrl(options.adminOrigin);
  const isDevelopment = options.nodeEnv === "development";
  const logger = new Logger("Auth");
  const hasDevFixedCode = (email: string) =>
    isDevelopment && email.toLowerCase().endsWith(DEV_FIXED_CODE_DOMAIN);
  return betterAuth({
    // The full `@repo/db` schema is passed (not just the four auth
    // tables): the adapter only looks up the models it needs by name, and
    // every table uses Better Auth's default model names (ADR-021 §7
    // "kept exactly as in the Better Auth documentation").
    database: drizzleAdapter(db, { provider: "pg", schema }),
    secret: options.secret,
    baseURL: options.baseUrl,
    trustedOrigins: [options.adminOrigin, ...options.trustedOrigins],
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
      // ADR-035 §2: no password in the app. Password sign-in stays for the
      // backoffice and admin 2FA; only the API's test instance signs up
      // with a password.
      disableSignUp: !options.allowPasswordSignUp,
      // ADR-022/ADR-023: sent through the `notifications` platform module
      // (Resend), never throws (logs only) per NotificationsService's own
      // contract.
      sendResetPassword: async ({ user, url }) => {
        const html = await renderResetPasswordEmail({ url, logoUrl });
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
        const html = await renderVerifyEmail({ url, logoUrl });
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
    session: {
      // ADR-035 §3: how the session was opened; only `password_2fa`
      // carries admin rights. `input: false` keeps it out of
      // `/update-session` and every other client-supplied body.
      additionalFields: {
        authMethod: { type: "string", required: false, input: false },
      },
    },
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
      // ADR-035 §2: sign-in and sign-up by Sign-in code. Plugin defaults
      // kept (6 digits, 5 min, 3 attempts, 3 requests / 60 s per IP on its
      // paths); the first valid code creates the account.
      emailOTP({
        resendStrategy: "rotate",
        storeOTP: "hashed",
        // `undefined` falls back to the plugin's random 6-digit code.
        generateOTP: ({ email }) => (hasDevFixedCode(email) ? DEV_FIXED_CODE : undefined),
        sendVerificationOTP: async ({ email, otp, type }) => {
          if (isDevelopment) {
            logger.log(`Sign-in code (${type}) for ${email}: ${otp}`);
          }
          if (hasDevFixedCode(email)) {
            return;
          }
          const html = await renderSignInCodeEmail({ otp, logoUrl });
          await notifications.sendAuthEmail({
            to: email,
            subject: "Votre code de connexion Nervo",
            html,
            // No `user` here (the account may not exist yet), ADR-035 §2.
            idempotencyKey: `sign-in-code/${email}-${otp}`,
          });
        },
      }),
      // ADR-022 §5: 2FA mandatory for admins. Adds `user.twoFactorEnabled`,
      // checked directly by `AdminGuard` — no separate "2FA required" flag.
      twoFactor({
        issuer: "Nervo",
        otpOptions: {
          period: 5,
          sendOTP: async ({ user, otp }) => {
            const html = await renderAdminOtpEmail({ otp, email: user.email, logoUrl });
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
      session: {
        create: {
          // ADR-035 §3: recomputed from the endpoint that opens the session,
          // never inherited (Better Auth copies the previous session's
          // fields when it rotates one, e.g. on 2FA enrollment).
          before: async (session, ctx) => ({
            data: { ...session, authMethod: sessionAuthMethodFor(ctx) },
          }),
        },
      },
      user: {
        create: {
          // ADR-035 §8: `user_signed_up` at the account's creation only, by
          // Sign-in code or Google; a later sign-in creates no user.
          after: async (user, ctx) => {
            const method = signUpMethodFor(ctx);
            if (method) {
              analytics.capture(ANALYTICS_EVENTS.USER_SIGNED_UP, user.id, { method });
            }
          },
        },
        update: {
          after: async () => {
            // Intentionally empty (see comment above).
          },
        },
      },
    },
  });
}
