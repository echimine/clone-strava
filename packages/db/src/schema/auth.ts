import { boolean, integer, pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

/**
 * Better Auth core tables (ADR-009, ADR-017), kept in the `public` schema
 * exactly as Better Auth's own schema generator would produce them
 * (ADR-021 §7: "`public` is the shared kernel ... Better Auth tables, kept
 * exactly as in the Better Auth documentation"), plus the admin plugin's
 * `role`/`banned`/`banReason`/`banExpires` (user) and `impersonatedBy`
 * (session) columns.
 *
 * Deviation from Better Auth's own defaults: identifiers are typed `uuid`
 * with `defaultRandom()` rather than Better Auth's default `text` id
 * (a non-dashed random string), to follow ADR-017 ("Identifiers: uuid ...
 * the others by the server"). Better Auth always supplies an id on insert,
 * so the DB default is only a fallback; `apps/api` must configure
 * `advanced.database.generateId` (or an id generator) to emit UUIDs so the
 * values Better Auth writes match this column type.
 *
 * `user.twoFactorEnabled` and the `twoFactor` table are the `twoFactor`
 * plugin's own schema (ADR-022 §5), field names/types kept exactly as
 * Better Auth's schema generator defines them (`better-auth/dist/plugins/
 * two-factor/schema.mjs`).
 */

/** `user.role` (ADR-017, ADR-009 admin guard). */
export const userRoleEnum = pgEnum("user_role", ["user", "admin"]);

export const user = pgTable("user", {
  id: uuid("id").defaultRandom().primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: boolean("email_verified").notNull().default(false),
  image: text("image"),
  // Admin plugin (ADR-017 §"Additions compared to slide 09").
  role: userRoleEnum("role").notNull().default("user"),
  banned: boolean("banned").notNull().default(false),
  banReason: text("ban_reason"),
  banExpires: timestamp("ban_expires", { withTimezone: true }),
  // `twoFactor` plugin (ADR-022 §5): checked directly by `AdminGuard`.
  twoFactorEnabled: boolean("two_factor_enabled").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const session = pgTable("session", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: uuid("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  token: text("token").notNull().unique(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  // Admin plugin: which admin is impersonating this session, if any.
  impersonatedBy: uuid("impersonated_by").references(() => user.id, { onDelete: "set null" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const account = pgTable("account", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: uuid("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  accessTokenExpiresAt: timestamp("access_token_expires_at", { withTimezone: true }),
  refreshTokenExpiresAt: timestamp("refresh_token_expires_at", { withTimezone: true }),
  scope: text("scope"),
  password: text("password"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const verification = pgTable("verification", {
  id: uuid("id").defaultRandom().primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

/** `twoFactor` plugin (ADR-022 §5): one row per user with 2FA configured. */
export const twoFactor = pgTable("two_factor", {
  id: uuid("id").defaultRandom().primaryKey(),
  secret: text("secret").notNull(),
  backupCodes: text("backup_codes").notNull(),
  userId: uuid("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" }),
  verified: boolean("verified").notNull().default(true),
  failedVerificationCount: integer("failed_verification_count").notNull().default(0),
  lockedUntil: timestamp("locked_until", { withTimezone: true }),
});
