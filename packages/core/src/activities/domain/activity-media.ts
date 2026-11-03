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

/**
 * A Media of an athlete's Gallery (ADR-037 §9) with the Activity it belongs to, for the viewer's
 * "titre · Voir l'activité ›" pill.
 */
export interface GalleryMediaRecord extends ActivityMediaRecord {
  activity: { id: string; title: string; startedAt: Date };
}

/** One keyset page of a Gallery: `nextCursor` is null on the last page. */
export interface GalleryMediaPage {
  items: GalleryMediaRecord[];
  nextCursor: string | null;
}
