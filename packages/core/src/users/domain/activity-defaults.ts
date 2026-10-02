import type { Visibility } from "@repo/contracts";

/** Profile settings the `activities` module needs (ADR-019 §5 step 6, ADR-028 §5). */
export interface UserActivityDefaults {
  defaultVisibility: Visibility;
  privacyZoneRadiusM: number;
}

/** ADR-017 column defaults, used when the user has no profile row yet. */
export const DEFAULT_USER_ACTIVITY_DEFAULTS: UserActivityDefaults = {
  defaultVisibility: "public",
  privacyZoneRadiusM: 200,
};
