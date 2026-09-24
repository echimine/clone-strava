import { date, integer, pgSchema, real, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/** `users` module (ADR-017, ADR-021 §1/§7): owns `user_profile`. */
export const usersSchema = pgSchema("users");

export const unitSystemEnum = usersSchema.enum("unit_system", ["metric", "imperial"]);
export const profileVisibilityEnum = usersSchema.enum("visibility", ["public", "followers", "private"]);

export const userProfile = usersSchema.table("user_profile", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  firstName: text("first_name"),
  lastName: text("last_name"),
  avatarUrl: text("avatar_url"),
  country: text("country"),
  city: text("city"),
  birthDate: date("birth_date"),
  gender: text("gender"),
  weightKg: real("weight_kg"),
  unitSystem: unitSystemEnum("unit_system").notNull().default("metric"),
  defaultVisibility: profileVisibilityEnum("default_visibility").notNull().default("public"),
  privacyZoneRadiusM: integer("privacy_zone_radius_m").notNull().default(200),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});
