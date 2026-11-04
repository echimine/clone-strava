import { z } from "zod";

/**
 * The parts of RevenueCat's REST API v2 responses `sync-subscription` reads (ADR-038 §12).
 * Validated loosely: RevenueCat may add fields and states, and times are milliseconds since
 * the epoch. v1 is never called: its read creates the customer.
 */

/** `customer.active_entitlement`: an entitlement the customer has now, as RevenueCat computes it. */
export const revenueCatActiveEntitlementSchema = z.looseObject({
  entitlement_id: z.string(),
  expires_at: z.number().nullable(),
});

/** `GET /v2/projects/{project_id}/customers/{customer_id}`. */
export const revenueCatCustomerSchema = z.looseObject({
  id: z.string(),
  active_entitlements: z
    .looseObject({ items: z.array(revenueCatActiveEntitlementSchema) })
    .nullish()
    .transform((list) => list?.items ?? []),
});
export type RevenueCatCustomer = z.infer<typeof revenueCatCustomerSchema>;

/**
 * `subscription`: one source of an entitlement. A Promotional Premium grant is a subscription
 * of the `promotional` store, without a product.
 */
export const revenueCatSubscriptionSchema = z.looseObject({
  id: z.string(),
  product_id: z.string().nullable(),
  starts_at: z.number(),
  current_period_ends_at: z.number().nullable(),
  ends_at: z.number().nullable(),
  gives_access: z.boolean(),
  /** `will_renew`, `will_not_renew`, `will_change_product`, `has_already_renewed`… */
  auto_renewal_status: z.string(),
  /** `trialing`, `active`, `expired`, `in_grace_period`, `in_billing_retry`… */
  status: z.string(),
  /** `app_store`, `promotional`, `play_store`… */
  store: z.string(),
  environment: z.string().nullish(),
  entitlements: z
    .looseObject({ items: z.array(z.looseObject({ id: z.string() })) })
    .nullish()
    .transform((list) => list?.items.map((entitlement) => entitlement.id) ?? []),
});
export type RevenueCatSubscription = z.infer<typeof revenueCatSubscriptionSchema>;

/** `GET /v2/projects/{project_id}/customers/{customer_id}/subscriptions` (one page). */
export const revenueCatSubscriptionListSchema = z.looseObject({
  items: z.array(revenueCatSubscriptionSchema),
  next_page: z.string().nullish(),
});
export type RevenueCatSubscriptionList = z.infer<typeof revenueCatSubscriptionListSchema>;
