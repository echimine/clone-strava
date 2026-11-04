import { z } from "zod";

/** Longest reason an Administrator may type. */
export const ADMIN_REASON_MAX_LENGTH = 1000;

/**
 * The reason of a Sanction (ADR-038 §4): free text, required, never empty once trimmed. The
 * athlete reads it. A route that requires it is declared `@Audited(..., { reason: "required" })`,
 * which answers `400 reason_required` before the body is validated.
 */
export const adminReasonSchema = z
  .string({ error: "Le motif est obligatoire" })
  .trim()
  .min(1, "Le motif est obligatoire")
  .max(ADMIN_REASON_MAX_LENGTH);

/** An optional reason (actions that are not Sanctions): an empty one counts as none. */
export const adminOptionalReasonSchema = z
  .string()
  .trim()
  .max(ADMIN_REASON_MAX_LENGTH)
  .optional()
  .transform((reason) => (reason ? reason : undefined));

/** Body of a Sanction that takes nothing but its reason (`{ reason }`). */
export const adminReasonBodySchema = z.object({ reason: adminReasonSchema });
export type AdminReasonBody = z.infer<typeof adminReasonBodySchema>;

/** Body of an action whose reason is optional (`{ reason? }`). */
export const adminOptionalReasonBodySchema = z.object({ reason: adminOptionalReasonSchema });
export type AdminOptionalReasonBody = z.infer<typeof adminOptionalReasonBodySchema>;

/** Error code of a missing or blank required reason (`400`). */
export const ADMIN_REASON_REQUIRED_CODE = "reason_required";
