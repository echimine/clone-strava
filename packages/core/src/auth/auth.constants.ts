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
  /**
   * Keeps `POST /api/auth/sign-up/email` open. Password sign-up is closed
   * everywhere (ADR-035 §2) except in the API's test instance, whose
   * password-based specs create their accounts this way.
   */
  allowPasswordSignUp?: boolean;
  /**
   * Turns on the dev Sign-in code helpers (ADR-035 §2): codes written to
   * the logs, fixed code `000000` for `@stravaclone.test` addresses. Only
   * the API in `NODE_ENV=development` sets it; off by default.
   */
  devSignInCodes?: boolean;
  /**
   * The team's contact address (`CONTACT_EMAIL`, ADR-038 §4): returned with a banned athlete's
   * `403 BANNED_USER` for the app's « Compte suspendu ». None when not configured.
   */
  contactEmail?: string;
}
