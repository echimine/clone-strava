import { date, integer, pgSchema, primaryKey, real, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";
import { sportType } from "./sports.js";

/** `users` module (ADR-017, ADR-021 §1/§7): owns `user_profile` and `user_sport`. */
export const usersSchema = pgSchema("users");

export const unitSystemEnum = usersSchema.enum("unit_system", ["metric", "imperial"]);
export const profileVisibilityEnum = usersSchema.enum("visibility", ["public", "followers", "private"]);
/** ADR-035 §4: on the profile, `null` = never asked. */
export const genderEnum = usersSchema.enum("gender", ["male", "female", "non_binary", "undisclosed"]);
export const athleteLevelEnum = usersSchema.enum("athlete_level", [
  "beginner",
  "intermediate",
  "advanced",
  "professional",
]);
export const goalEnum = usersSchema.enum("goal", [
  "compete",
  "discover_routes",
  "health",
  "meet_athletes",
  "train_for_event",
  "build_habit",
]);

export const userProfile = usersSchema.table("user_profile", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  firstName: text("first_name"),
  lastName: text("last_name"),
  /** ADR-037 §2: `avatars/{userId}/{avatarId}.jpg`, signed by the API when read; null = initials. */
  avatarKey: text("avatar_key"),
  /** ADR-036 §3 (amended): "Modifier le profil"'s Bio, at most 300 characters. */
  bio: text("bio"),
  /** ISO 3166-1 alpha-2 code, e.g. `FR` (ADR-036 §3). */
  country: text("country"),
  city: text("city"),
  birthDate: date("birth_date"),
  gender: genderEnum("gender"),
  /** ADR-035 §4: the Onboarding's Level answer. */
  level: athleteLevelEnum("level"),
  /** ADR-035 §4: `null` = never went through the Onboarding, `[]` = Goals skipped. */
  goals: goalEnum("goals").array(),
  weightKg: real("weight_kg"),
  unitSystem: unitSystemEnum("unit_system").notNull().default("metric"),
  defaultVisibility: profileVisibilityEnum("default_visibility").notNull().default("public"),
  privacyZoneRadiusM: integer("privacy_zone_radius_m").notNull().default(200),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

/** Practiced sports (ADR-035 §4): `position` keeps the order of selection. */
export const userSport = usersSchema.table(
  "user_sport",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    sportCode: text("sport_code")
      .notNull()
      .references(() => sportType.code),
    position: integer("position").notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.sportCode] })],
);
