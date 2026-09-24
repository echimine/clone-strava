/**
 * Minimal user representation exposed to other modules (ADR-021 §2 rule 5:
 * "cross-module references are identifiers only", §6: batch read methods
 * return plain public types, never Drizzle rows).
 */
export interface UserSummary {
  userId: string;
  firstName: string | null;
  lastName: string | null;
  avatarUrl: string | null;
}
