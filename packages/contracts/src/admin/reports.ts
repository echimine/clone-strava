import { z } from "zod";
import { mediaSchema } from "../activities/media.js";
import { userRoleSchema } from "../common/enums.js";
import {
  reportCaseStatusSchema,
  reportReasonSchema,
  reportTargetTypeSchema,
} from "../moderation/report.js";
import { auditPersonSchema } from "./audit.js";
import {
  adminListResponseSchema,
  adminPageQuerySchema,
  adminPeriodShape,
  adminSortQuerySchema,
  isOrderedPeriod,
  periodOrderIssue,
} from "./list.js";
import { ADMIN_REASON_MAX_LENGTH } from "./reason.js";

/** « À traiter » (`open`) or « Clos » (`actioned`, `dismissed`, `target_gone`). */
export const adminReportCaseStateSchema = z.enum(["open", "closed"]);
export type AdminReportCaseState = z.infer<typeof adminReportCaseStateSchema>;

/** Hours after which an open case shows a red badge (ADR-038 §10). */
export const REPORT_CASE_OVERDUE_HOURS = 24;

/** Characters of the first Report's copy a list row previews. */
export const REPORT_CASE_PREVIEW_LENGTH = 120;

/**
 * `GET /v1/admin/reports?state&targetType&reason&from&to&sort&order&page&pageSize` (ADR-038 §10):
 * one row per case. Oldest opened first by default, then the most reported. `reason` keeps the
 * cases where at least one Report gives it; `from`/`to` are Paris days of the opening.
 */
export const adminReportCaseListQuerySchema = adminPageQuerySchema
  .extend({
    state: adminReportCaseStateSchema.default("open"),
    targetType: reportTargetTypeSchema.optional(),
    reason: reportReasonSchema.optional(),
    ...adminSortQuerySchema(["openedAt", "reportCount", "closedAt"], { sort: "openedAt", order: "asc" }).shape,
    ...adminPeriodShape,
  })
  .refine(isOrderedPeriod, periodOrderIssue);
export type AdminReportCaseListQuery = z.infer<typeof adminReportCaseListQuerySchema>;

/** An athlete a case names: `displayName` null once the account is deleted (« Compte supprimé »). */
export const adminReportAthleteSchema = z.object({
  id: z.uuid(),
  displayName: z.string().nullable(),
  avatarUrl: z.string().nullable(),
});
export type AdminReportAthlete = z.infer<typeof adminReportAthleteSchema>;

export const adminReportCaseListItemSchema = z.object({
  id: z.uuid(),
  targetType: reportTargetTypeSchema,
  targetId: z.uuid(),
  status: reportCaseStatusSchema,
  openedAt: z.iso.datetime(),
  closedAt: z.iso.datetime().nullable(),
  /** The target's author (the athlete themself for an athlete); their Avatar is an athlete's thumbnail. */
  author: adminReportAthleteSchema,
  /** The first Report's copy, truncated (comment text, Activity title, athlete name); null once closed. */
  preview: z.string().nullable(),
  reportCount: z.number().int().nonnegative(),
  /** Every reason given by the case's Reports, in the order of the reason list. */
  reasons: z.array(reportReasonSchema),
});
export type AdminReportCaseListItem = z.infer<typeof adminReportCaseListItemSchema>;

export const adminReportCaseListResponseSchema = adminListResponseSchema(adminReportCaseListItemSchema);
export type AdminReportCaseListResponse = z.infer<typeof adminReportCaseListResponseSchema>;

/** The target as it is now (ADR-038 §10); null in the detail once it is gone. */
export const adminReportTargetContentSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("comment"),
    body: z.string(),
    createdAt: z.iso.datetime(),
    updatedAt: z.iso.datetime().nullable(),
    /** The Activity the comment is under, linked to its admin detail; null if gone. */
    activity: z.object({ id: z.uuid(), title: z.string() }).nullable(),
  }),
  z.object({
    kind: z.literal("activity"),
    title: z.string(),
    description: z.string().nullable(),
    startedAt: z.iso.datetime(),
    media: z.array(mediaSchema),
  }),
  z.object({
    kind: z.literal("athlete"),
    displayName: z.string(),
    bio: z.string().nullable(),
    avatarUrl: z.string().nullable(),
  }),
]);
export type AdminReportTargetContent = z.infer<typeof adminReportTargetContentSchema>;

/** A Report's copy of the target's texts, as sent (ADR-038 §9); Media and Avatar by count or flag only. */
export const adminReportCopySchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("comment"), body: z.string() }),
  z.object({
    kind: z.literal("activity"),
    title: z.string(),
    description: z.string().nullable(),
    mediaCount: z.number().int().nonnegative(),
  }),
  z.object({ kind: z.literal("athlete"), name: z.string(), bio: z.string().nullable(), hadAvatar: z.boolean() }),
]);
export type AdminReportCopy = z.infer<typeof adminReportCopySchema>;

export const adminReportSchema = z.object({
  id: z.uuid(),
  /** Null once the reporter's account is deleted (« Compte supprimé »). */
  reporter: auditPersonSchema.nullable(),
  reason: reportReasonSchema,
  note: z.string().nullable(),
  createdAt: z.iso.datetime(),
  /** Null once the case is closed (the copy is erased) or the author's account deleted. */
  copy: adminReportCopySchema.nullable(),
  /** « modifié depuis le signalement »: the copy differs from the current content. */
  changedSince: z.boolean(),
});
export type AdminReport = z.infer<typeof adminReportSchema>;

/** The target's author: link, Banned badge, Reports received, past Sanctions (from the Journal). */
export const adminReportAuthorSchema = adminReportAthleteSchema.extend({
  /** Null once the account is deleted. */
  role: userRoleSchema.nullable(),
  banned: z.boolean(),
  reportsReceived: z.number().int().nonnegative(),
  pastSanctions: z.number().int().nonnegative(),
});
export type AdminReportAuthor = z.infer<typeof adminReportAuthorSchema>;

/** `GET /v1/admin/reports/:caseId` (ADR-038 §10). */
export const adminReportCaseDetailSchema = z.object({
  id: z.uuid(),
  targetType: reportTargetTypeSchema,
  targetId: z.uuid(),
  status: reportCaseStatusSchema,
  openedAt: z.iso.datetime(),
  closedAt: z.iso.datetime().nullable(),
  /** Who closed it; null for « Système » (or while open). */
  closedBy: auditPersonSchema.nullable(),
  closeNote: z.string().nullable(),
  /** The target now; null once it is gone. */
  current: adminReportTargetContentSchema.nullable(),
  author: adminReportAuthorSchema,
  /** Oldest first. */
  reports: z.array(adminReportSchema),
  /**
   * Whether « Sanctionné » is offered: a Sanction is in the Journal since the opening, on the
   * target or on its author. Otherwise only « Rejeter ».
   */
  canResolve: z.boolean(),
});
export type AdminReportCaseDetail = z.infer<typeof adminReportCaseDetailSchema>;

/** `POST /v1/admin/reports/:caseId/resolve` / `dismiss` body: an optional closing note. */
export const adminReportCaseCloseBodySchema = z.object({
  note: z
    .string()
    .trim()
    .max(ADMIN_REASON_MAX_LENGTH)
    .optional()
    .transform((note) => (note ? note : undefined)),
});
export type AdminReportCaseCloseBody = z.input<typeof adminReportCaseCloseBodySchema>;

export const adminReportCaseCloseResponseSchema = z.object({
  id: z.uuid(),
  status: reportCaseStatusSchema,
  closedAt: z.iso.datetime(),
  /** Reports closed with the case. */
  count: z.number().int().nonnegative(),
});
export type AdminReportCaseCloseResponse = z.infer<typeof adminReportCaseCloseResponseSchema>;

/** `409` codes of the closing endpoints; `404 report_case_not_found` for an unknown case. */
export const ADMIN_REPORT_ERROR_CODES = {
  notFound: "report_case_not_found",
  closed: "case_closed",
  noSanction: "no_sanction",
} as const;
