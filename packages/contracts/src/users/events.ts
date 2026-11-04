/**
 * Domain events of the `users` area, emitted by `apps/api` after an account deletion committed
 * (ADR-021 §3, ADR-038 §13). Same process only: the API's listeners (moderation's auto-close,
 * #213) see it, the worker does not.
 */
export const ACCOUNT_DELETED_EVENT = "users.account.deleted";

/** `bySanction`: deleted by an Administrator (`user.delete`), not by the athlete themselves. */
export type AccountDeletedEvent = { userId: string; bySanction: boolean };
