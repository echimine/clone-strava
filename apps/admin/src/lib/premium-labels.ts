import type { AdminPremiumState, AdminUserPremiumFilter, PromotionalPremiumDuration } from "@repo/contracts";

/**
 * Premium's French words (ADR-038 §12), shared by the users list and the user sheet's
 * « Premium » section. Always « Premium », never « Abonnement » (a Follow in the app).
 */
export const premiumStateLabels: Record<AdminPremiumState, string> = {
  never: "Jamais abonné",
  trial: "Essai",
  paying: "Payant",
  promotional: "Premium offert",
  grace_period: "Période de grâce",
  billing_issue: "Problème de paiement",
  cancelled: "Résilié",
  expired: "Expiré",
};

/** The users list's Premium filter. */
export const premiumFilterLabels: Record<AdminUserPremiumFilter, string> = {
  paying: "Payant",
  trial: "Essai",
  promotional: "Premium offert",
  billing_issue: "Problème de paiement",
  cancelled: "Résilié",
  expired: "Expiré",
};

export const promotionalDurationLabels: Record<PromotionalPremiumDuration, string> = {
  "1m": "1 mois",
  "3m": "3 mois",
  "6m": "6 mois",
  "12m": "12 mois",
};
