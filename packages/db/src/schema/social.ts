import { sql } from "drizzle-orm";
import { boolean, check, index, pgSchema, primaryKey, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/** `social` module (ADR-017, ADR-021 §1/§7): owns `follow`, `follow_settings` and `athlete_block`. */
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

/**
 * ADR-038 §8: `blocker_id` blocked `blocked_id`. Two-way in effect (each sees the other as
 * nonexistent), one row per blocker. Survives a Ban; cascades with either account.
 */
export const athleteBlock = socialSchema.table(
  "athlete_block",
  {
    blockerId: uuid("blocker_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    blockedId: uuid("blocked_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.blockerId, table.blockedId] }),
    // The viewer filter reads both directions: who blocked the viewer.
    index("athlete_block_blocked_idx").on(table.blockedId),
    check("athlete_block_not_self_check", sql`${table.blockerId} <> ${table.blockedId}`),
  ],
);
