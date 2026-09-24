/** DI token for the raw Better Auth instance (ADR-021 §1, ADR-009 §3). */
export const AUTH_INSTANCE = Symbol("AUTH_INSTANCE");

/**
 * Options for `AuthModule.forRoot` (ADR-009 §3). Kept in this file, not
 * `auth.module.ts`, so `create-auth-instance.ts` can import the type
 * without a module <-> module cycle (`.dependency-cruiser.cjs`
 * `no-circular`).
 */
export interface AuthModuleOptions {
  secret: string;
  baseUrl: string;
  trustedOrigins: string[];
}
