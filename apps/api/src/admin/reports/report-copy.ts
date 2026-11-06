import {
  REPORT_CASE_PREVIEW_LENGTH,
  reportSnapshotSchemas,
  type AdminReportCopy,
  type AuditTargetType,
  type ReportTargetType,
} from "@repo/contracts";
import type { z } from "zod";

/** A target type's snapshot: the copy a Report keeps, and the target's texts now (ADR-038 §9). */
export type SnapshotOf<K extends ReportTargetType> = z.infer<(typeof reportSnapshotSchemas)[K]>;

/** What the moderation queue does differently for each target type (ADR-038 §10). */
interface ReportTargetKind<K extends ReportTargetType> {
  /** The Journal's type for the target: a Sanction on it lets the case close as « Sanctionné ». */
  auditTarget: AuditTargetType;
  /** The copy as the backoffice shows it: texts, a Media count, whether there was an Avatar. */
  toAdminCopy(snapshot: SnapshotOf<K>): AdminReportCopy;
  /** « modifié depuis le signalement »: the copy differs from the target now. */
  changed(copy: SnapshotOf<K>, current: SnapshotOf<K>): boolean;
  /** A list row's preview: the comment text, the Activity title or the athlete name. */
  previewText(snapshot: SnapshotOf<K>): string;
}

/** One entry per target type: the only place the queue branches on it, but for reading the target. */
export const REPORT_TARGET_KINDS: { [K in ReportTargetType]: ReportTargetKind<K> } = {
  comment: {
    auditTarget: "comment",
    toAdminCopy: (copy) => ({ kind: "comment", body: copy.body }),
    changed: (copy, current) => copy.body !== current.body,
    previewText: (copy) => copy.body,
  },
  activity: {
    auditTarget: "activity",
    toAdminCopy: (copy) => ({
      kind: "activity",
      title: copy.title,
      description: copy.description,
      mediaCount: copy.mediaIds.length,
    }),
    changed: (copy, current) =>
      copy.title !== current.title ||
      copy.description !== current.description ||
      !sameSet(copy.mediaIds, current.mediaIds),
    previewText: (copy) => copy.title,
  },
  athlete: {
    auditTarget: "user",
    toAdminCopy: (copy) => ({ kind: "athlete", name: copy.name, bio: copy.bio, hadAvatar: copy.avatarKey !== null }),
    changed: (copy, current) =>
      copy.name !== current.name || copy.bio !== current.bio || copy.avatarKey !== current.avatarKey,
    previewText: (copy) => copy.name,
  },
  // ADR-039 §11: the queue leaves Segment cases out until #219; only the copy is typed here.
  segment: {
    auditTarget: "segment",
    toAdminCopy: (copy) => ({ kind: "segment", name: copy.name }),
    changed: (copy, current) => copy.name !== current.name,
    previewText: (copy) => copy.name,
  },
};

/** A snapshot typed by its target type. */
export type TypedSnapshot<K extends ReportTargetType = ReportTargetType> = {
  [P in K]: { kind: P; snapshot: SnapshotOf<P> };
}[K];

/** A Report's stored copy, typed by its case's target (ADR-038 §9); null when erased or unreadable. */
export function readCopy<K extends ReportTargetType>(
  targetType: K,
  snapshot: Record<string, unknown> | null,
): TypedSnapshot<K> | null {
  if (snapshot === null) {
    return null;
  }
  const parsed = reportSnapshotSchemas[targetType].safeParse(snapshot);
  return parsed.success ? ({ kind: targetType, snapshot: parsed.data } as TypedSnapshot<K>) : null;
}

export function toAdminCopy<K extends ReportTargetType>(copy: TypedSnapshot<K>): AdminReportCopy {
  return kind(copy.kind).toAdminCopy(copy.snapshot);
}

/**
 * « modifié depuis le signalement » (ADR-038 §10): the copy differs from the target now. A gone
 * target or an erased copy is not « modified ».
 */
export function changedSince(copy: TypedSnapshot | null, current: TypedSnapshot | null): boolean {
  if (copy === null || current === null || copy.kind !== current.kind) {
    return false;
  }
  return kind(copy.kind).changed(copy.snapshot, current.snapshot as SnapshotOf<typeof copy.kind>);
}

/** A list row's preview: the first Report's comment text, Activity title or athlete name, truncated. */
export function previewOf(copy: TypedSnapshot | null): string | null {
  if (copy === null) {
    return null;
  }
  const chars = [...kind(copy.kind).previewText(copy.snapshot).trim()];
  return chars.length > REPORT_CASE_PREVIEW_LENGTH
    ? `${chars.slice(0, REPORT_CASE_PREVIEW_LENGTH).join("").trimEnd()}…`
    : chars.join("");
}

/** The Journal's type for a case's target. */
export function auditTargetOf(targetType: ReportTargetType): AuditTargetType {
  return REPORT_TARGET_KINDS[targetType].auditTarget;
}

/** `REPORT_TARGET_KINDS[k]` typed by `k` (TypeScript does not correlate the union by itself). */
function kind<K extends ReportTargetType>(k: K): ReportTargetKind<K> {
  return REPORT_TARGET_KINDS[k];
}

function sameSet(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((id) => b.includes(id));
}
