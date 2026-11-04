import { z } from "zod";
import { subscriptionPeriodTypeSchema, subscriptionStoreSchema } from "../common/enums.js";
import { adminReasonSchema } from "./reason.js";

/**
 * Premium on the user sheet (ADR-038 §12): the state derived from the `premium` row of
 * `user_subscription`, read in our tables only, never from RevenueCat.
 *
 * - `never`: no row (« Jamais abonné »).
 * - `trial`, `paying`: Premium now and renewing (« Essai », « Payant »).
 * - `promotional`: Premium now, offered by an Administrator (« Premium offert »).
 * - `grace_period`: past its end, still Premium during Apple's grace period (« Période de grâce »).
 * - `billing_issue`: Premium now, a payment failed (« Problème de paiement »).
 * - `cancelled`: Premium until its end, will not renew (« Résilié jusqu'au … »).
 * - `expired`: a row that no longer gives Premium (« Expiré »).
 */
export const adminPremiumStateSchema = z.enum([
  "never",
  "trial",
  "paying",
  "promotional",
  "grace_period",
  "billing_issue",
  "cancelled",
  "expired",
]);
export type AdminPremiumState = z.infer<typeof adminPremiumStateSchema>;

/**
 * The users list's Premium filter (ADR-038 §12): « Payant », « Essai », « Premium offert »,
 * « Problème de paiement » (the grace period included), « Résilié », « Expiré ».
 */
export const adminUserPremiumFilterSchema = z.enum([
  "paying",
  "trial",
  "promotional",
  "billing_issue",
  "cancelled",
  "expired",
]);
export type AdminUserPremiumFilter = z.infer<typeof adminUserPremiumFilterSchema>;

/** The `premium` row as the sheet details it. */
export const adminPremiumDetailSchema = z.object({
  /** The store's product id; null for Promotional Premium. */
  productId: z.string().nullable(),
  store: subscriptionStoreSchema.nullable(),
  periodType: subscriptionPeriodTypeSchema.nullable(),
  purchasedAt: z.iso.datetime().nullable(),
  /** The end of the period: renewal date when it renews, end otherwise. */
  expiresAt: z.iso.datetime().nullable(),
  gracePeriodExpiresAt: z.iso.datetime().nullable(),
  willRenew: z.boolean(),
  unsubscribeDetectedAt: z.iso.datetime().nullable(),
  billingIssueDetectedAt: z.iso.datetime().nullable(),
  /** « Sandbox » badge: a test purchase. */
  sandbox: z.boolean(),
  syncedAt: z.iso.datetime().nullable(),
});
export type AdminPremiumDetail = z.infer<typeof adminPremiumDetailSchema>;

/** One RevenueCat event received for the athlete: never its raw JSON. */
export const adminPremiumEventSchema = z.object({
  id: z.string(),
  /** RevenueCat's event type (`INITIAL_PURCHASE`, `RENEWAL`, `NON_RENEWING_PURCHASE`…). */
  type: z.string(),
  /** When it happened at RevenueCat, else when we received it. */
  occurredAt: z.iso.datetime(),
  productId: z.string().nullable(),
  /** RevenueCat's store (`APP_STORE`, `PROMOTIONAL`…): tells the sources apart. */
  store: z.string().nullable(),
  /** RevenueCat's period type (`TRIAL`, `NORMAL`, `PROMOTIONAL`…). */
  periodType: z.string().nullable(),
  expiresAt: z.iso.datetime().nullable(),
  sandbox: z.boolean(),
});
export type AdminPremiumEvent = z.infer<typeof adminPremiumEventSchema>;

/** The most RevenueCat events the sheet lists, newest first. */
export const ADMIN_PREMIUM_HISTORY_LIMIT = 100;

/** `GET /v1/admin/users/:id/premium` (ADR-038 §12): the sheet's « Premium » section. */
export const adminUserPremiumSchema = z.object({
  /**
   * RevenueCat's API v2 is configured (key, project, entitlement): without it « Offrir »,
   * « Retirer » and « Resynchroniser » are disabled with « RevenueCat non configuré ».
   */
  configured: z.boolean(),
  state: adminPremiumStateSchema,
  /** Null when the athlete never had a `premium` row. */
  detail: adminPremiumDetailSchema.nullable(),
  history: z.array(adminPremiumEventSchema),
  /** The customer in the RevenueCat dashboard; null without a project id. */
  revenueCatUrl: z.url().nullable(),
});
export type AdminUserPremium = z.infer<typeof adminUserPremiumSchema>;

/** Promotional Premium's closed choice of length (ADR-038 §12): 1, 3, 6 or 12 months. */
export const promotionalPremiumDurationSchema = z.enum(["1m", "3m", "6m", "12m"]);
export type PromotionalPremiumDuration = z.infer<typeof promotionalPremiumDurationSchema>;

/** Months of each Promotional Premium length. */
export const PROMOTIONAL_PREMIUM_MONTHS: Record<PromotionalPremiumDuration, number> = {
  "1m": 1,
  "3m": 3,
  "6m": 6,
  "12m": 12,
};

/** `POST /v1/admin/users/:id/premium/promotional` (`premium.grant`, reason required, no e-mail). */
export const adminGrantPremiumBodySchema = z.object({
  duration: promotionalPremiumDurationSchema,
  reason: adminReasonSchema,
});
export type AdminGrantPremiumBody = z.infer<typeof adminGrantPremiumBodySchema>;

/** `POST /v1/admin/users/:id/premium/sync` (`premium.sync`) answers `202`: the job is queued. */
export const adminPremiumSyncResponseSchema = z.object({ queued: z.boolean() });
export type AdminPremiumSyncResponse = z.infer<typeof adminPremiumSyncResponseSchema>;

/**
 * Error codes of the Premium actions: `503 revenuecat_not_configured` without the RevenueCat
 * configuration, `502 revenuecat_unavailable` when RevenueCat refuses or fails.
 */
export const ADMIN_PREMIUM_ERROR_CODES = {
  notConfigured: "revenuecat_not_configured",
  unavailable: "revenuecat_unavailable",
} as const;
