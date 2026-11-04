import { z } from "zod";

/**
 * `POST /v1/me/account-deletion { code }` (ADR-038 §13): the Sign-in code sent to the account's
 * e-mail by `POST /v1/me/account-deletion/code`, re-verifying the athlete before an immediate and
 * final deletion.
 */
export const accountDeletionRequestSchema = z.object({
  code: z.string().trim().min(1).max(12),
});
export type AccountDeletionRequest = z.infer<typeof accountDeletionRequestSchema>;

/**
 * Error codes of the athlete's account deletion: `403 admin_cannot_delete_account` (« Un
 * administrateur ne peut pas supprimer son compte »); `400` for a wrong, expired or exhausted
 * code (ask for a new one).
 */
export const ACCOUNT_DELETION_ERROR_CODES = {
  adminCannotDelete: "admin_cannot_delete_account",
  invalidCode: "invalid_code",
  codeExpired: "code_expired",
  tooManyAttempts: "too_many_attempts",
} as const;
