import { sql } from "drizzle-orm";
import { check, index, jsonb, pgSchema, text, timestamp, unique, uniqueIndex, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/**
 * `moderation` module (ADR-038 §9, §10, §18: layer 0). Owns `report_case` and `report`.
 *
 * Reports stay individual, but each target has at most one `open` case; the first Report opens
 * it, the next ones join it. A case keeps its target as a plain id (no foreign key): the case
 * outlives its target, and closes as `target_gone` when it disappears (#213).
 */
export const moderationSchema = pgSchema("moderation");

/** What a Report is about. */
export const reportTargetTypeEnum = moderationSchema.enum("report_target_type", [
  "comment",
  "activity",
  "athlete",
  "segment",
]);

/** "Spam ou publicité", "Harcèlement ou propos haineux", "Contenu sexuel ou violent", "Usurpation d'identité", "Autre". */
export const reportReasonEnum = moderationSchema.enum("report_reason", [
  "spam",
  "harassment",
  "sexual_or_violent",
  "impersonation",
  "other",
]);

/** `open` until an Administrator closes it (`actioned` / `dismissed`) or its target disappears (`target_gone`). */
export const reportCaseStatusEnum = moderationSchema.enum("report_case_status", [
  "open",
  "actioned",
  "dismissed",
  "target_gone",
]);

export const reportCase = moderationSchema.table(
  "report_case",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    targetType: reportTargetTypeEnum("target_type").notNull(),
    targetId: uuid("target_id").notNull(),
    /**
     * The target's author (the athlete themself for an `athlete` target). No foreign key: see
     * above. Null only for a `segment` with no creator (ADR-039 §11: Nervo, or creator deleted).
     */
    targetUserId: uuid("target_user_id"),
    status: reportCaseStatusEnum("status").notNull().default("open"),
    openedAt: timestamp("opened_at", { withTimezone: true }).notNull().defaultNow(),
    closedAt: timestamp("closed_at", { withTimezone: true }),
    /** The Administrator who closed it, or null for "Système" (or while open). */
    closedBy: uuid("closed_by"),
    closeNote: text("close_note"),
  },
  (table) => [
    // ADR-038 §18: one open case per target; after closing, a new Report opens a new case.
    uniqueIndex("report_case_open_target_idx")
      .on(table.targetType, table.targetId)
      .where(sql`${table.status} = 'open'`),
    // ADR-038 §10: the queue, oldest open case first.
    index("report_case_status_opened_at_idx").on(table.status, table.openedAt),
    // ADR-038 §10: Reports received by an athlete (user sheet).
    index("report_case_target_user_idx").on(table.targetUserId),
    // ADR-039 §11: only a Segment may have no target athlete (`::text`: the enum value is new).
    check(
      "report_case_target_user_check",
      sql`${table.targetUserId} is not null or ${table.targetType}::text = 'segment'`,
    ),
  ],
);

export const report = moderationSchema.table(
  "report",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    caseId: uuid("case_id")
      .notNull()
      .references(() => reportCase.id, { onDelete: "cascade" }),
    /**
     * Null once the reporter's account is deleted ("Athlète supprimé", ADR-038 §13); the note is
     * erased just before (`ModerationService.eraseNotesOfReporter`), the Report and its case stay.
     */
    reporterId: uuid("reporter_id").references(() => user.id, { onDelete: "set null" }),
    reason: reportReasonEnum("reason").notNull(),
    note: text("note"),
    /**
     * Copy of the target's texts when the Report was sent (ADR-038 §9), shaped by the case's
     * `target_type` (`reportSnapshotSchemas` in `@repo/contracts`); Media and Avatar only by
     * reference. Set to null when the case closes or the author's account is deleted.
     */
    snapshot: jsonb("snapshot").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    // ADR-038 §9: one Report per reporter per case. Also serves the reporter's own lookups
    // (viewer filter, 24 h limit).
    unique("report_reporter_case_unique").on(table.reporterId, table.caseId),
    index("report_case_idx").on(table.caseId),
    index("report_reporter_created_at_idx").on(table.reporterId, table.createdAt),
  ],
);
