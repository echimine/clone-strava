import { index, integer, pgSchema, real, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { activity } from "./activities.js";
import { user } from "./auth.js";
import { geometryLineString, geometryPoint } from "./postgis.js";
import { sportType } from "./sports.js";

/** `segments` module (ADR-017, ADR-021 §1/§7): owns `segment`, `segment_effort`. */
export const segmentsSchema = pgSchema("segments");

export const segment = segmentsSchema.table(
  "segment",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    name: text("name").notNull(),
    sportTypeCode: text("sport_type_code")
      .notNull()
      .references(() => sportType.code),
    path: geometryLineString("path"),
    startPoint: geometryPoint("start_point"),
    endPoint: geometryPoint("end_point"),
    distanceM: real("distance_m"),
    avgGrade: real("avg_grade"),
  },
  (table) => [
    // ADR-017 "Main indexes": segments near a route.
    index("segment_path_gist_idx").using("gist", table.path),
    index("segment_start_point_gist_idx").using("gist", table.startPoint),
  ],
);

export const segmentEffort = segmentsSchema.table(
  "segment_effort",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    activityId: uuid("activity_id")
      .notNull()
      .references(() => activity.id, { onDelete: "cascade" }),
    segmentId: uuid("segment_id")
      .notNull()
      .references(() => segment.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    elapsedTimeS: integer("elapsed_time_s").notNull(),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull(),
    // Denormalized (ADR-017): recomputed in the worker on every new effort.
    rank: integer("rank"),
  },
  (table) => [
    // ADR-017 "Main indexes": segment leaderboard.
    index("segment_effort_segment_elapsed_time_idx").on(table.segmentId, table.elapsedTimeS),
  ],
);
