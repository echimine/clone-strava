/** Hierarchical cache keys for the `premium` feature (TanStack Query query-keys guide). */
export const premiumKeys = {
  all: ["premium"] as const,
  user: (userId: string) => [...premiumKeys.all, userId] as const,
};

/**
 * Caches of other features this one may not import: the users feature's (`userKeys.all`: the
 * sheet's Premium badge, the list) and the Journal's (`auditKeys.all`: every action adds an
 * entry, the sheet's Historique included).
 */
export const usersKey = ["users"] as const;
export const journalKey = ["audit"] as const;
