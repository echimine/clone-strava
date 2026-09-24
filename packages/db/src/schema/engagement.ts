import { sql } from "drizzle-orm";
import { index, pgSchema, primaryKey, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { activity } from "./activities.js";
import { user } from "./auth.js";

/**
 * `engagement` module (ADR-017, amended by ADR-021 §1: split from `social`
 * to break the `social` <-> `activities` dependency cycle). Owns `kudos`
 * and `comment`.
 */
export const engagementSchema = pgSchema("engagement");

export const kudos = engagementSchema.table(
  "kudos",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    activityId: uuid("activity_id")
      .notNull()
      .references(() => activity.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.activityId] })],
);

export const comment = engagementSchema.table(
  "comment",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    activityId: uuid("activity_id")
      .notNull()
      .references(() => activity.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    body: text("body").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    // ADR-017 "Main indexes": an activity's (non-deleted) comments.
    index("comment_activity_created_at_idx")
      .on(table.activityId, table.createdAt)
      .where(sql`${table.deletedAt} is null`),
  ],
);
