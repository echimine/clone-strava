import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { admin, bearer } from "better-auth/plugins";
import { schema, type Database } from "@repo/db";
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
export function createAuthInstance(db: Database, options: AuthModuleOptions) {
  return betterAuth({
    // The full `@repo/db` schema is passed (not just the four auth
    // tables): the adapter only looks up the models it needs by name, and
    // every table uses Better Auth's default model names (ADR-021 §7
    // "kept exactly as in the Better Auth documentation").
    database: drizzleAdapter(db, { provider: "pg", schema }),
    secret: options.secret,
    baseURL: options.baseUrl,
    trustedOrigins: options.trustedOrigins,
    emailAndPassword: { enabled: true },
    // ADR-017: identifiers are `uuid`, not Better Auth's default text id.
    advanced: { database: { generateId: "uuid" } },
    plugins: [admin(), bearer()],
  });
}
