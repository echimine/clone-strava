import type { AdminPremiumState, AdminUserListQuery, AthleteLevel, UserRole, Visibility } from "@repo/contracts";

/** The users list's filters (ADR-038 §5), without the page. */
export type AdminUserFilter = Omit<AdminUserListQuery, "page" | "pageSize">;

/** One account of the backoffice users list, as read in one query. */
export interface AdminUserRow {
  id: string;
  email: string;
  /** Better Auth's account name: the fallback while the profile has none. */
  name: string;
  role: UserRole;
  createdAt: Date;
  banned: boolean;
  banReason: string | null;
  banExpires: Date | null;
  /** `provider_id`s of the linked Better Auth accounts (`google`, `credential`). */
  providerIds: string[];
  activityCount: number;
  lastActivityAt: Date | null;
  isPremium: boolean;
  /** The Premium state (ADR-038 §12), the rule of `subscriptions`' `premiumState` in SQL. */
  premiumState: AdminPremiumState;
  /** The end of the Premium period, grace period included. */
  premiumEndsAt: Date | null;
}

/** The athlete profile the user sheet shows (ADR-038 §5): never birth date, gender nor weight. */
export interface AdminProfile {
  firstName: string | null;
  lastName: string | null;
  bio: string | null;
  city: string | null;
  country: string | null;
  sports: string[];
  level: AthleteLevel | null;
  defaultVisibility: Visibility;
}

/** The first name of a reset name (ADR-038 §5); the last name is emptied. */
export const RESET_FIRST_NAME = "Athlète";
