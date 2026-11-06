import {
  index,
  integer,
  pgSchema,
  primaryKey,
  real,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { activity } from "./activities.js";
import { user } from "./auth.js";
import { geometryLineStringZ, geometryPoint } from "./postgis.js";
import { sportType } from "./sports.js";

/**
 * `segments` module (ADR-017, ADR-021 §1/§7, amended by ADR-039 §17): owns `segment`,
 * `segment_effort`, `segment_favorite`, `segment_creation`, `excluded_source_key`, `activity_matching`.
 */
export const segmentsSchema = pgSchema("segments");

/** ADR-039 §5: drawn by an athlete, or created by Nervo from open data. */
export const segmentOriginEnum = segmentsSchema.enum("segment_origin", ["athlete", "nervo"]);
/** ADR-039 §5: climb category from the length × grade rule; null under a score of 8,000. */
export const climbCategoryEnum = segmentsSchema.enum("climb_category", ["hc", "1", "2", "3", "4"]);
/** ADR-038 §16: an Effort's verdict. */
export const effortStatusEnum = segmentsSchema.enum("effort_status", ["valid", "suspicious", "rejected"]);
/** ADR-039 §8: the athlete's 1st, 2nd, 3rd time at the date of the Activity. */
export const effortMedalEnum = segmentsSchema.enum("effort_medal", ["gold", "silver", "bronze"]);

export const segment = segmentsSchema.table(
  "segment",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    name: text("name").notNull(),
    sportTypeCode: text("sport_type_code")
      .notNull()
      .references(() => sportType.code),
    /** ADR-039 §5: never shown; null for a Nervo Segment or once the creator's account is deleted. */
    createdBy: uuid("created_by").references(() => user.id, { onDelete: "set null" }),
    origin: segmentOriginEnum("origin").notNull().default("athlete"),
    /** ADR-039 §10: a Nervo Segment's stable key in the generator's output. */
    sourceKey: text("source_key").unique(),
    /** ADR-039 §5: granted and withdrawn by an Administrator. */
    verifiedAt: timestamp("verified_at", { withTimezone: true }),
    /** ADR-039 §5: Z is the altitude from the `ElevationService` (or the generator's model). */
    path: geometryLineStringZ("path"),
    startPoint: geometryPoint("start_point"),
    endPoint: geometryPoint("end_point"),
    distanceM: real("distance_m"),
    avgGrade: real("avg_grade"),
    maxGrade: real("max_grade"),
    elevationGainM: real("elevation_gain_m"),
    minAltitudeM: real("min_altitude_m"),
    maxAltitudeM: real("max_altitude_m"),
    climbCategory: climbCategoryEnum("climb_category"),
    /** Encoded polyline of the path, for the map cards (ADR-039 §12). */
    mapPolyline: text("map_polyline"),
    /** ADR-039 §7: set by the last page of `match-segment-history`. */
    historyMatchedAt: timestamp("history_matched_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    // ADR-017 "Main indexes": segments near a route; ADR-039 §6 prefilter on both ends.
    index("segment_path_gist_idx").using("gist", table.path),
    index("segment_start_point_gist_idx").using("gist", table.startPoint),
    index("segment_end_point_gist_idx").using("gist", table.endPoint),
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
    /** Elapsed time between the interpolated crossings, Pauses included (ADR-039 §6). */
    elapsedTimeS: integer("elapsed_time_s").notNull(),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull(),
    /** Points of the stored cleaned trace around the Effort (ADR-039 §6). */
    startIndex: integer("start_index").notNull(),
    endIndex: integer("end_index").notNull(),
    /** In the privacy zone when either is below the athlete's current radius, read at read time. */
    minDistanceToActivityStartM: real("min_distance_to_activity_start_m").notNull(),
    minDistanceToActivityEndM: real("min_distance_to_activity_end_m").notNull(),
    status: effortStatusEnum("status").notNull().default("valid"),
    /** Replayed silently whenever the athlete's history on the Segment changes (ADR-039 §8). */
    medal: effortMedalEnum("medal"),
  },
  (table) => [
    // ADR-039 §6: several Efforts per Activity, even on the same Segment.
    uniqueIndex("segment_effort_activity_segment_start_idx").on(
      table.activityId,
      table.segmentId,
      table.startIndex,
    ),
    // ADR-039 §17: Leaderboard, and Medals per (athlete, Segment).
    index("segment_effort_segment_status_time_idx").on(table.segmentId, table.status, table.elapsedTimeS),
    index("segment_effort_user_segment_started_at_idx").on(table.userId, table.segmentId, table.startedAt),
  ],
);

/** ADR-039 §5: a star, private and free. */
export const segmentFavorite = segmentsSchema.table(
  "segment_favorite",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    segmentId: uuid("segment_id")
      .notNull()
      .references(() => segment.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.segmentId] })],
);

/**
 * ADR-039 §5: one row per Segment an athlete created, kept when the Segment is deleted, so the
 * quota of 10 per rolling 24 h counts creations and a deletion gives none back.
 */
export const segmentCreation = segmentsSchema.table(
  "segment_creation",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("segment_creation_user_created_idx").on(table.userId, table.createdAt)],
);

/** ADR-039 §10: Nervo keys an Administrator deleted; the import never brings them back. */
export const excludedSourceKey = segmentsSchema.table("excluded_source_key", {
  sourceKey: text("source_key").primaryKey(),
  excludedAt: timestamp("excluded_at", { withTimezone: true }).notNull().defaultNow(),
});

/** ADR-039 §6, §13: the matching version an Activity was last matched with. */
export const activityMatching = segmentsSchema.table("activity_matching", {
  activityId: uuid("activity_id")
    .primaryKey()
    .references(() => activity.id, { onDelete: "cascade" }),
  version: integer("version").notNull(),
  matchedAt: timestamp("matched_at", { withTimezone: true }).notNull().defaultNow(),
});
