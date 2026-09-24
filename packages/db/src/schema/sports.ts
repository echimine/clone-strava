import { boolean, integer, pgSchema, text } from "drizzle-orm/pg-core";

/** `sports` module (ADR-017, ADR-021 §1/§7): owns `sport_type`, populated by migration. */
export const sportsSchema = pgSchema("sports");

export const paceUnitEnum = sportsSchema.enum("pace_unit", ["pace", "speed"]);

export const sportType = sportsSchema.table("sport_type", {
  code: text("code").primaryKey(),
  category: text("category").notNull(),
  iconName: text("icon_name").notNull(),
  tracksDistance: boolean("tracks_distance").notNull().default(true),
  tracksElevation: boolean("tracks_elevation").notNull().default(true),
  usesGps: boolean("uses_gps").notNull().default(true),
  paceUnit: paceUnitEnum("pace_unit").notNull().default("pace"),
  minDurationS: integer("min_duration_s").notNull().default(60),
  minDistanceM: integer("min_distance_m").notNull().default(0),
  displayOrder: integer("display_order").notNull().default(0),
  isActive: boolean("is_active").notNull().default(true),
});
