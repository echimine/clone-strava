import type {
  ActivityImport,
  ActivitySource,
  ActivityStats,
  ProcessingStatus,
  Visibility,
} from "@repo/contracts";
import type { ActivityMediaRecord } from "./activity-media.js";

/**
 * How an e-mail or the backoffice names an Activity: "votre Activité « Sortie du dimanche » du
 * 2 novembre" (ADR-038 §4). `userId` is its author, the athlete a Sanction concerns.
 */
export interface ActivityLabel {
  id: string;
  userId: string;
  title: string;
  startedAt: Date;
}

/** Filters of the backoffice Activities list (ADR-038 §11); `from`/`to` are Paris days. */
export interface AdminActivityFilter {
  q?: string;
  status?: ProcessingStatus;
  source?: ActivitySource;
  sportTypeCode?: string;
  visibility?: Visibility;
  userId?: string;
  from?: string;
  to?: string;
}

/** One row of the backoffice Activities list; the caller adds the athlete's identity. */
export interface AdminActivityRow {
  id: string;
  userId: string;
  title: string;
  sportTypeCode: string;
  processingStatus: ProcessingStatus;
  source: ActivitySource;
  visibility: Visibility;
  startedAt: Date;
  createdAt: Date;
  distanceM: number | null;
}

/**
 * An Activity as the backoffice opens it (ADR-038 §11): the `activities` module's part. `route`
 * is the public trace (`activity_track.route`, privacy zone applied), never the raw one. The
 * caller adds the athlete, signs the Media, and adds engagement and efforts.
 */
export interface AdminActivityRecord extends AdminActivityRow {
  description: string | null;
  processingError: string | null;
  processingAttempts: number;
  endedAt: Date;
  updatedAt: Date;
  processedAt: Date | null;
  stats: ActivityStats | null;
  route: [number, number][] | null;
  locationName: string | null;
  media: ActivityMediaRecord[];
  import: ActivityImport | null;
}
