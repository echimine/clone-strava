import {
  REPORT_CASE_PREVIEW_LENGTH,
  reportSnapshotSchemas,
  type AdminReportCopy,
  type ActivityReportSnapshot,
  type AthleteReportSnapshot,
  type CommentReportSnapshot,
  type ReportTargetType,
} from "@repo/contracts";

/** A Report's stored copy, typed by its case's target (ADR-038 §9); null when erased or unreadable. */
export type StoredCopy =
  | { kind: "comment"; snapshot: CommentReportSnapshot }
  | { kind: "activity"; snapshot: ActivityReportSnapshot }
  | { kind: "athlete"; snapshot: AthleteReportSnapshot };

/** What a copy is compared with: the target's texts now, and its Media ids or Avatar key. */
export type CurrentTexts =
  | { kind: "comment"; body: string }
  | { kind: "activity"; title: string; description: string | null; mediaIds: string[] }
  | { kind: "athlete"; name: string; bio: string | null; avatarKey: string | null };

export function readCopy(targetType: ReportTargetType, snapshot: Record<string, unknown> | null): StoredCopy | null {
  if (snapshot === null) {
    return null;
  }
  switch (targetType) {
    case "comment": {
      const parsed = reportSnapshotSchemas.comment.safeParse(snapshot);
      return parsed.success ? { kind: "comment", snapshot: parsed.data } : null;
    }
    case "activity": {
      const parsed = reportSnapshotSchemas.activity.safeParse(snapshot);
      return parsed.success ? { kind: "activity", snapshot: parsed.data } : null;
    }
    case "athlete": {
      const parsed = reportSnapshotSchemas.athlete.safeParse(snapshot);
      return parsed.success ? { kind: "athlete", snapshot: parsed.data } : null;
    }
  }
}

/** The copy as the backoffice shows it: texts, a Media count, whether there was an Avatar. */
export function toAdminCopy(copy: StoredCopy): AdminReportCopy {
  switch (copy.kind) {
    case "comment":
      return { kind: "comment", body: copy.snapshot.body };
    case "activity":
      return {
        kind: "activity",
        title: copy.snapshot.title,
        description: copy.snapshot.description,
        mediaCount: copy.snapshot.mediaIds.length,
      };
    case "athlete":
      return {
        kind: "athlete",
        name: copy.snapshot.name,
        bio: copy.snapshot.bio,
        hadAvatar: copy.snapshot.avatarKey !== null,
      };
  }
}

/**
 * « modifié depuis le signalement » (ADR-038 §10): the copy differs from the target now. A gone
 * target or an erased copy is not « modified ».
 */
export function changedSince(copy: StoredCopy | null, current: CurrentTexts | null): boolean {
  if (copy === null || current === null || copy.kind !== current.kind) {
    return false;
  }
  if (copy.kind === "comment" && current.kind === "comment") {
    return copy.snapshot.body !== current.body;
  }
  if (copy.kind === "activity" && current.kind === "activity") {
    return (
      copy.snapshot.title !== current.title ||
      copy.snapshot.description !== current.description ||
      !sameSet(copy.snapshot.mediaIds, current.mediaIds)
    );
  }
  if (copy.kind === "athlete" && current.kind === "athlete") {
    return (
      copy.snapshot.name !== current.name ||
      copy.snapshot.bio !== current.bio ||
      copy.snapshot.avatarKey !== current.avatarKey
    );
  }
  return false;
}

/** A list row's preview: the first Report's comment text, Activity title or athlete name, truncated. */
export function previewOf(copy: StoredCopy | null): string | null {
  if (copy === null) {
    return null;
  }
  const text =
    copy.kind === "comment" ? copy.snapshot.body : copy.kind === "activity" ? copy.snapshot.title : copy.snapshot.name;
  const chars = [...text.trim()];
  return chars.length > REPORT_CASE_PREVIEW_LENGTH
    ? `${chars.slice(0, REPORT_CASE_PREVIEW_LENGTH).join("").trimEnd()}…`
    : chars.join("");
}

function sameSet(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((id) => b.includes(id));
}
