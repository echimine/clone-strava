/**
 * How a session was opened (ADR-035 §3). Only `password_2fa` carries admin
 * rights; the others are "weak" for `/v1/admin/*`.
 */
export const SESSION_AUTH_METHODS = ["password_2fa", "password", "email_otp", "google"] as const;
export type SessionAuthMethod = (typeof SESSION_AUTH_METHODS)[number];

/** The parts of a Better Auth endpoint context the mapping reads. */
export interface AuthEndpointRoute {
  path?: string;
  params?: Record<string, string | undefined>;
}

/**
 * Maps the Better Auth endpoint that creates a session to its
 * `authMethod` (ADR-035 §3). Better Auth exposes the route pattern as
 * `ctx.path` (`/callback/:id`, provider in `params.id`); the concrete
 * `/callback/google` is accepted too. Any other path (password change,
 * impersonation, 2FA enable…) gives `null`: a weak session, never
 * `password_2fa`.
 */
export function sessionAuthMethodFor(route: AuthEndpointRoute | null | undefined): SessionAuthMethod | null {
  const path = route?.path ?? "";
  if (path.startsWith("/two-factor/verify-")) return "password_2fa";
  if (path === "/sign-in/email" || path === "/sign-up/email") return "password";
  if (path === "/sign-in/email-otp") return "email_otp";
  if (path === "/sign-in/social") return "google";
  if (path === "/callback/google") return "google";
  if (path === "/callback/:id" && route?.params?.id === "google") return "google";
  return null;
}

/** How an account was created, as `user_signed_up` tells it (ADR-035 §8). */
export type SignUpMethod = "google" | "email_code";

/**
 * Maps the Better Auth endpoint that creates an account to its
 * `user_signed_up` method: the Sign-in code or Google. Any other path
 * (password sign-up of the backoffice and the tests, admin creation…)
 * gives `null`: no event.
 */
export function signUpMethodFor(route: AuthEndpointRoute | null | undefined): SignUpMethod | null {
  switch (sessionAuthMethodFor(route)) {
    case "email_otp":
      return "email_code";
    case "google":
      return "google";
    default:
      return null;
  }
}
