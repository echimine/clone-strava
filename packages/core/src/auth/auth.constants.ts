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
  /**
   * Origin of the backoffice: trusted by Better Auth (cross-subdomain
   * cookie, ADR-022) and host of the auth emails' wordmark (ADR-032 §2).
   */
  adminOrigin: string;
  /** Origins trusted besides the backoffice's (e.g. the iOS app's scheme). */
  trustedOrigins: string[];
  googleClientId: string;
  googleClientSecret: string;
  resendApiKey: string;
}
