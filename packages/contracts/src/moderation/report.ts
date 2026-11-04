import { z } from "zod";

/** `moderation.report_target_type` (ADR-038 §9, §18): what a Report is about. */
export const reportTargetTypeSchema = z.enum(["comment", "activity", "athlete"]);
export type ReportTargetType = z.infer<typeof reportTargetTypeSchema>;

/**
 * `moderation.report_reason` (ADR-038 §9): "Spam ou publicité", "Harcèlement ou propos haineux",
 * "Contenu sexuel ou violent", "Usurpation d'identité" (an athlete only), "Autre" (note required).
 */
export const reportReasonSchema = z.enum(["spam", "harassment", "sexual_or_violent", "impersonation", "other"]);
export type ReportReason = z.infer<typeof reportReasonSchema>;

/** `moderation.report_case.status` (ADR-038 §10, §18). */
export const reportCaseStatusSchema = z.enum(["open", "actioned", "dismissed", "target_gone"]);
export type ReportCaseStatus = z.infer<typeof reportCaseStatusSchema>;

/** The reporter's optional note (ADR-038 §9), required with `other`. */
export const REPORT_NOTE_MAX_LENGTH = 500;

/** At most this many Reports per athlete over a sliding 24 h (ADR-038 §9), then `429`. */
export const REPORT_LIMIT_PER_DAY = 20;

/**
 * `POST /v1/reports` body (ADR-038 §9). The rules spanning fields (a note with `other`,
 * `impersonation` for an athlete only) answer `422 note_required` / `422 reason_not_allowed`.
 */
export const createReportRequestSchema = z.object({
  targetType: reportTargetTypeSchema,
  targetId: z.uuid(),
  reason: reportReasonSchema,
  note: z.string().max(REPORT_NOTE_MAX_LENGTH).optional(),
});
export type CreateReportRequest = z.infer<typeof createReportRequestSchema>;

/** `201` a new Report, `200` this athlete already has a Report in the target's open case ("Déjà signalé"). */
export const createReportResponseSchema = z.object({
  id: z.uuid(),
});
export type CreateReportResponse = z.infer<typeof createReportResponseSchema>;

/**
 * Copy of the target's texts when the Report was sent (ADR-038 §9), stored in
 * `moderation.report.snapshot` and shaped by the case's `target_type`. Media and Avatar only by
 * reference, never a file. Erased (null) when the case closes or the author's account is deleted.
 */
export const commentReportSnapshotSchema = z.object({
  body: z.string(),
  /** The Activity the comment is under, to link it from the backoffice. */
  activityId: z.uuid(),
});
export const activityReportSnapshotSchema = z.object({
  title: z.string(),
  description: z.string().nullable(),
  mediaIds: z.array(z.uuid()),
});
export const athleteReportSnapshotSchema = z.object({
  /** The name everyone saw. */
  name: z.string(),
  bio: z.string().nullable(),
  /** The Avatar's object key, never signed here. */
  avatarKey: z.string().nullable(),
});
export type CommentReportSnapshot = z.infer<typeof commentReportSnapshotSchema>;
export type ActivityReportSnapshot = z.infer<typeof activityReportSnapshotSchema>;
export type AthleteReportSnapshot = z.infer<typeof athleteReportSnapshotSchema>;

/** The snapshot schema for each target type. */
export const reportSnapshotSchemas = {
  comment: commentReportSnapshotSchema,
  activity: activityReportSnapshotSchema,
  athlete: athleteReportSnapshotSchema,
} as const satisfies Record<ReportTargetType, z.ZodType>;
export type ReportSnapshot = CommentReportSnapshot | ActivityReportSnapshot | AthleteReportSnapshot;
