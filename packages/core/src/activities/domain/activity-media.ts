import type { MediaKind } from "@repo/contracts";

/**
 * An `activity_media` row as the `activities` module hands it out (ADR-037 §12): `folderKey` is
 * the Media's bucket folder, for `apps/api` to sign its files (ADR-037 §1). It never leaves the API.
 */
export interface ActivityMediaRecord {
  id: string;
  activityId: string;
  kind: MediaKind;
  width: number;
  height: number;
  /** Null for a photo. */
  durationMs: number | null;
  folderKey: string;
}
