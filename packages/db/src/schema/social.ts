import { sql } from "drizzle-orm";
import { boolean, check, index, pgSchema, primaryKey, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/** `social` module (ADR-017, ADR-021 §1/§7): owns `follow` and `follow_settings`. */
export const socialSchema = pgSchema("social");

export const followStatusEnum = socialSchema.enum("follow_status", ["pending", "accepted"]);

export const follow = socialSchema.table(
  "follow",
  {
    followerId: uuid("follower_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    followeeId: uuid("followee_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    status: followStatusEnum("status").notNull().default("pending"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.followerId, table.followeeId] }),
    // ADR-017 "Main indexes": a user's followers.
    index("follow_followee_status_idx").on(table.followeeId, table.status),
    // ADR-036 §1: the "following" list and counts.
    index("follow_follower_status_idx").on(table.followerId, table.status),
    // ADR-036 §1: nobody follows themselves.
    check("follow_not_self_check", sql`${table.followerId} <> ${table.followeeId}`),
  ],
);

/** ADR-036 §1: "Approuver mes abonnés". No row means `approve_followers = false`. */
export const followSettings = socialSchema.table("follow_settings", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  approveFollowers: boolean("approve_followers").notNull().default(false),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});
