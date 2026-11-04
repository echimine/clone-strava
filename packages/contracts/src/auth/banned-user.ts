import { z } from "zod";

/** Code of Better Auth's `403` when a banned athlete signs in (admin plugin, ADR-038 §6). */
export const BANNED_USER_CODE = "BANNED_USER";

/**
 * Body of the `403 BANNED_USER` a sign-in gets while the account's Ban is active (ADR-038 §6),
 * by Sign-in code or Google: what the app's « Compte suspendu » screen shows. Sending a Sign-in
 * code to a banned athlete is still accepted; only the sign-in itself fails.
 */
export const bannedUserErrorSchema = z.object({
  code: z.literal(BANNED_USER_CODE),
  /** A French sentence for any other client. */
  message: z.string(),
  /** End of the Ban; null for a permanent one (« définitivement »). */
  bannedUntil: z.iso.datetime().nullable(),
  /** The reason the Administrator typed. */
  banReason: z.string().nullable(),
  /** The team's contact address (`CONTACT_EMAIL`); null when not configured. */
  contactEmail: z.string().nullable(),
});
export type BannedUserError = z.infer<typeof bannedUserErrorSchema>;
