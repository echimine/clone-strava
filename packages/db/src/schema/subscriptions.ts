import { boolean, jsonb, pgSchema, primaryKey, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { user } from "./auth.js";

/**
 * `subscriptions` module (ADR-014, ADR-017 "Addition"): owns
 * `user_subscription` and `revenuecat_event`. Written only by the worker's
 * `sync-subscription` job, never by a Better Auth endpoint.
 */
export const subscriptionsSchema = pgSchema("subscriptions");

export const subscriptionStoreEnum = subscriptionsSchema.enum("store", ["app_store"]);
export const subscriptionPeriodTypeEnum = subscriptionsSchema.enum("period_type", [
  "trial",
  "intro",
  "normal",
]);
export const subscriptionEnvironmentEnum = subscriptionsSchema.enum("environment", [
  "sandbox",
  "production",
]);

export const userSubscription = subscriptionsSchema.table(
  "user_subscription",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    // `premium` for the MVP (ADR-017): one row per user and per entitlement.
    entitlementId: text("entitlement_id").notNull().default("premium"),
    isActive: boolean("is_active").notNull().default(false),
    productId: text("product_id"),
    store: subscriptionStoreEnum("store"),
    periodType: subscriptionPeriodTypeEnum("period_type"),
    willRenew: boolean("will_renew").notNull().default(false),
    purchasedAt: timestamp("purchased_at", { withTimezone: true }),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    gracePeriodExpiresAt: timestamp("grace_period_expires_at", { withTimezone: true }),
    billingIssueDetectedAt: timestamp("billing_issue_detected_at", { withTimezone: true }),
    unsubscribeDetectedAt: timestamp("unsubscribe_detected_at", { withTimezone: true }),
    environment: subscriptionEnvironmentEnum("environment"),
    syncedAt: timestamp("synced_at", { withTimezone: true }),
  },
  (table) => [
    // ADR-017 "Main indexes": premium check.
    primaryKey({ columns: [table.userId, table.entitlementId] }),
  ],
);

export const revenuecatEvent = subscriptionsSchema.table("revenuecat_event", {
  // RevenueCat's own event identifier (ADR-017): used to deduplicate webhook deliveries.
  id: text("id").primaryKey(),
  userId: uuid("user_id").references(() => user.id, { onDelete: "cascade" }),
  type: text("type").notNull(),
  payload: jsonb("payload").notNull(),
  receivedAt: timestamp("received_at", { withTimezone: true }).notNull().defaultNow(),
  processedAt: timestamp("processed_at", { withTimezone: true }),
});
