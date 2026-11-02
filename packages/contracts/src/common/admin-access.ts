import { z } from "zod";

/**
 * Error codes `AdminGuard` returns on `/v1/admin/*` (`403`), besides the
 * plain `forbidden` of a non-admin. The backoffice reacts to each one:
 * - `ADMIN_2FA_REQUIRED` (ADR-022 §5): the admin has not enabled 2FA yet,
 *   so it opens the 2FA setup screen;
 * - `ADMIN_STRONG_SESSION_REQUIRED` (ADR-035 §3): the session was not
 *   opened by password + second factor, so it signs out and goes back to
 *   the sign-in page.
 */
export const ADMIN_ACCESS_ERROR_CODES = {
  twoFactorRequired: "ADMIN_2FA_REQUIRED",
  strongSessionRequired: "ADMIN_STRONG_SESSION_REQUIRED",
} as const;

/** `GET /v1/admin`: answers `ok` when the session may use the admin routes. */
export const adminAccessResponseSchema = z.object({
  status: z.literal("ok"),
});
export type AdminAccessResponse = z.infer<typeof adminAccessResponseSchema>;
