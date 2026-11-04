import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/**
 * `accounts` queue (ADR-038 §13, ADR-011), owned by `users`: the cleanup outside the database
 * once an account is deleted. Enqueued by `apps/api`, run by `apps/worker`.
 */
export const ACCOUNTS_QUEUE_NAME = "accounts";
/**
 * `delete-account` job: the bucket prefixes `activities/`, `imports/`, `avatars/` of the
 * account, then its RevenueCat customer, then its PostHog person last, then the Journal entry
 * `user.delete.complete` (author « Système »). Idempotent: every step tolerates « already gone ».
 */
export const DELETE_ACCOUNT_JOB_NAME = "delete-account";

/** Deterministic job id (ADR-011 §2): one cleanup per account. */
export function deleteAccountJobId(userId: string): string {
  return `delete-account-${userId}`;
}

/**
 * `delete-account` payload. Only the account id: the bucket prefixes, the RevenueCat customer
 * (app user id) and the PostHog person (`distinct_id`) are all keyed on it, and the e-mail to
 * the athlete goes through the `emails` queue with its own data.
 */
export const deleteAccountJobSchema = z.object({
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type DeleteAccountJob = z.infer<typeof deleteAccountJobSchema>;
