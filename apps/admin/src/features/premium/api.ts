import {
  adminPremiumSyncResponseSchema,
  adminUserPremiumSchema,
  type AdminPremiumSyncResponse,
  type AdminUserPremium,
  type PromotionalPremiumDuration,
} from "@repo/contracts";
import { z } from "zod";
import { apiClient } from "@/lib/apiClient";

/** A `204` has no body. */
const noContent = z.undefined();

/** The user sheet's « Premium » section (ADR-038 §12): read in our tables only. */
export function getPremium(userId: string, signal?: AbortSignal): Promise<AdminUserPremium> {
  return apiClient(`/v1/admin/users/${userId}/premium`, adminUserPremiumSchema, { signal });
}

/** « Resynchroniser »: queues the sync with RevenueCat. */
export function syncPremium(userId: string): Promise<AdminPremiumSyncResponse> {
  return apiClient(`/v1/admin/users/${userId}/premium/sync`, adminPremiumSyncResponseSchema, { method: "POST" });
}

/** « Offrir le Premium » for 1, 3, 6 or 12 months; reason required, no e-mail. */
export function grantPremium(userId: string, duration: PromotionalPremiumDuration, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${userId}/premium/promotional`, noContent, {
    method: "POST",
    body: { duration, reason },
  });
}

/** « Retirer le Premium offert »; reason required, no e-mail. */
export function revokePremium(userId: string, reason: string): Promise<void> {
  return apiClient(`/v1/admin/users/${userId}/premium/promotional`, noContent, {
    method: "DELETE",
    body: { reason },
  });
}
