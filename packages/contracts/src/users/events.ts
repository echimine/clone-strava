/**
 * An account was deleted (ADR-038 §13), emitted by `apps/api` after the deletion committed: by
 * the athlete themself or by an Administrator as a Sanction (`bySanction`). The SQL cascade
 * removes the athlete's content without a per-item event, so listeners act on `userId` (the
 * moderation queue closes every open case on that athlete or their content, ADR-038 §10).
 */
export const ACCOUNT_DELETED_EVENT = "users.account.deleted";

export type AccountDeletedEvent = { userId: string; bySanction: boolean };
