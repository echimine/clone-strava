import { z } from "zod";
import { adminListResponseSchema, adminPageQuerySchema, adminPeriodShape, isOrderedPeriod, periodOrderIssue } from "./list.js";

/**
 * What an audit entry points at. `job` ids are `<queue>/<jobId>`; a batch has a type and no id.
 */
export const AUDIT_TARGET_TYPES = [
  "user",
  "activity",
  "media",
  "comment",
  "activity_import",
  "queue",
  "job",
  "report_case",
  "segment",
  "segment_effort",
] as const;
export const auditTargetTypeSchema = z.enum(AUDIT_TARGET_TYPES);
export type AuditTargetType = z.infer<typeof auditTargetTypeSchema>;

/**
 * The closed list of audit actions (ADR-038 §17), each with the type of its target. A route's
 * `@Audited("<action>")` takes its target type from here and its target id from the route
 * parameter `id` unless it says otherwise.
 */
export const AUDIT_ACTION_TARGETS = {
  // Users (ADR-038 §5, §13)
  "user.ban": "user",
  "user.unban": "user",
  "user.sign_out": "user",
  "user.name.reset": "user",
  "user.bio.reset": "user",
  "user.avatar.reset": "user",
  "user.role.grant": "user",
  "user.role.revoke": "user",
  "user.delete": "user",
  /** The `delete-account` job's cleanup outside the database, author "Système" (ADR-038 §13). */
  "user.delete.complete": "user",
  // Premium (ADR-038 §12)
  "premium.sync": "user",
  "premium.grant": "user",
  "premium.revoke": "user",
  // Activities (ADR-038 §11, §14)
  "activity.reprocess": "activity",
  "activity.recompute": "activity",
  "activity.delete": "activity",
  "activity.text.reset": "activity",
  "media.remove": "media",
  "comment.remove": "comment",
  "import.reprocess": "activity_import",
  // Batches: one entry, count and ids in `details` (ADR-038 §14)
  "activity.reprocess.batch": "activity",
  "activity.recompute.batch": "activity",
  "import.reprocess.batch": "activity_import",
  // Queues (ADR-038 §14)
  "queue.job.retry": "job",
  "queue.retry_failed": "queue",
  "queue.pause": "queue",
  "queue.resume": "queue",
  // Reports (ADR-038 §10)
  "report.resolve": "report_case",
  "report.dismiss": "report_case",
  // Segments (ADR-038 §16)
  "effort.accept": "segment_effort",
  "effort.reject": "segment_effort",
  "effort.restore": "segment_effort",
  "segment.rename": "segment",
  "segment.delete": "segment",
  // Better Auth hooks (ADR-038 §3): the Administrator is author and subject athlete.
  "admin.two_factor.enable": "user",
  "admin.two_factor.disable": "user",
} as const satisfies Record<string, AuditTargetType>;

export type AuditAction = keyof typeof AUDIT_ACTION_TARGETS;
export const AUDIT_ACTIONS = Object.keys(AUDIT_ACTION_TARGETS) as [AuditAction, ...AuditAction[]];
export const auditActionSchema = z.enum(AUDIT_ACTIONS);

/** Someone an entry names: `displayName` is null once the account is deleted ("Compte supprimé"). */
export const auditPersonSchema = z.object({
  id: z.uuid(),
  displayName: z.string().nullable(),
});
export type AuditPerson = z.infer<typeof auditPersonSchema>;

/** One line of the Journal (ADR-038 §3). */
export const auditEntrySchema = z.object({
  id: z.uuid(),
  createdAt: z.iso.datetime(),
  action: auditActionSchema,
  /** The Administrator; null for "Système". */
  actor: auditPersonSchema.nullable(),
  target: z.object({
    type: auditTargetTypeSchema,
    /** Null for a batch. */
    id: z.string().nullable(),
    /** Whether the target still exists, so the backoffice can link to it. */
    exists: z.boolean(),
  }),
  /** The athlete concerned, if any. */
  subject: auditPersonSchema.nullable(),
  reason: z.string().nullable(),
  /** The action's parameters only (a Ban's duration, a batch's ids), never a copy of content. */
  details: z.record(z.string(), z.unknown()).nullable(),
  requestId: z.string().nullable(),
});
export type AuditEntry = z.infer<typeof auditEntrySchema>;

/**
 * `GET /v1/admin/audit-entries?actorId&action&subjectUserId&from&to&page&pageSize`, newest
 * first. `from`/`to` are Paris days, both included.
 */
export const auditEntryListQuerySchema = adminPageQuerySchema
  .extend({
    actorId: z.uuid().optional(),
    action: auditActionSchema.optional(),
    subjectUserId: z.uuid().optional(),
    ...adminPeriodShape,
  })
  .refine(isOrderedPeriod, periodOrderIssue);
export type AuditEntryListQuery = z.infer<typeof auditEntryListQuerySchema>;

export const auditEntryListResponseSchema = adminListResponseSchema(auditEntrySchema);
export type AuditEntryListResponse = z.infer<typeof auditEntryListResponseSchema>;

/**
 * `GET /v1/admin/audit-entries/actors`: everyone who authored an entry, for the Journal's author
 * filter (former Administrators included), by name.
 */
export const auditActorListResponseSchema = z.object({
  items: z.array(auditPersonSchema),
});
export type AuditActorListResponse = z.infer<typeof auditActorListResponseSchema>;
