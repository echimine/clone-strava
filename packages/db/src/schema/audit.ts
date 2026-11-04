import { index, jsonb, pgSchema, text, timestamp, uuid } from "drizzle-orm/pg-core";

/**
 * `audit` module (ADR-038 §3, §18: layer 0). Owns `admin_audit_entry`, the Journal of every
 * admin write. Append-only on the application side and kept forever.
 *
 * No foreign key and no snapshot of a name or an e-mail: an entry outlives the accounts it
 * names, which the backoffice then shows as "Compte supprimé". `action` and `target_type` are
 * plain text, closed by the `AUDIT_ACTIONS` list of `@repo/contracts` (ADR-038 §17).
 */
export const auditSchema = pgSchema("audit");

export const adminAuditEntry = auditSchema.table(
  "admin_audit_entry",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    /** The Administrator, or null for "Système" (a job, an athlete's own account deletion). */
    actorId: uuid("actor_id"),
    action: text("action").notNull(),
    targetType: text("target_type").notNull(),
    /** Text, not uuid: a queue name or a BullMQ job id is a target too. */
    targetId: text("target_id"),
    /** The athlete concerned, e.g. the author of a removed comment. */
    subjectUserId: uuid("subject_user_id"),
    reason: text("reason"),
    /** The action's parameters only (a Ban's duration, a batch's ids), never a copy of content. */
    details: jsonb("details").$type<Record<string, unknown>>(),
    requestId: text("request_id"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("admin_audit_entry_subject_created_at_idx").on(table.subjectUserId, table.createdAt),
    index("admin_audit_entry_actor_created_at_idx").on(table.actorId, table.createdAt),
    index("admin_audit_entry_action_created_at_idx").on(table.action, table.createdAt),
  ],
);
