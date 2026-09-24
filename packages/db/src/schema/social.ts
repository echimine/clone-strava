import { index, pgSchema, primaryKey, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/** `social` module (ADR-017, ADR-021 §1/§7): owns `follow`. */
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
  ],
);
