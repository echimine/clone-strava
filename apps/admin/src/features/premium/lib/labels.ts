import type { SubscriptionPeriodType, SubscriptionStore } from "@repo/contracts";

export const storeLabels: Record<SubscriptionStore, string> = {
  app_store: "App Store",
  promotional: "Offert par l'équipe",
};

export const periodTypeLabels: Record<SubscriptionPeriodType, string> = {
  trial: "Essai",
  intro: "Offre de lancement",
  normal: "Payant",
  promotional: "Offert",
};

/** RevenueCat's event types; an unknown one shows as is. */
const eventTypeLabels: Record<string, string> = {
  INITIAL_PURCHASE: "Premier achat",
  RENEWAL: "Renouvellement",
  CANCELLATION: "Résiliation",
  UNCANCELLATION: "Résiliation annulée",
  NON_RENEWING_PURCHASE: "Achat sans renouvellement",
  EXPIRATION: "Expiration",
  BILLING_ISSUE: "Problème de paiement",
  PRODUCT_CHANGE: "Changement de produit",
  SUBSCRIPTION_PAUSED: "Mis en pause",
  SUBSCRIPTION_EXTENDED: "Prolongé",
  TRANSFER: "Transfert",
  TEMPORARY_ENTITLEMENT_GRANT: "Accès temporaire",
  TEST: "Test",
};

/** RevenueCat's stores and period types, as an event carries them (upper case). */
const eventSourceLabels: Record<string, string> = {
  APP_STORE: "App Store",
  MAC_APP_STORE: "Mac App Store",
  PROMOTIONAL: "Offert",
  TRIAL: "Essai",
  INTRO: "Offre de lancement",
  NORMAL: "Payant",
};

export function eventTypeLabel(type: string): string {
  return eventTypeLabels[type] ?? type;
}

/** « App Store · Essai », « Offert »…: tells the sources apart in the history. */
export function eventSourceLabel(store: string | null, periodType: string | null): string {
  const parts = [store, store === "PROMOTIONAL" ? null : periodType]
    .filter((part): part is string => part !== null)
    .map((part) => eventSourceLabels[part] ?? part);
  return parts.length > 0 ? parts.join(" · ") : "—";
}

const date = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short" });
const dateTime = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short", timeStyle: "short" });

export function formatDate(iso: string | null): string {
  return iso ? date.format(new Date(iso)) : "—";
}

export function formatDateTime(iso: string | null): string {
  return iso ? dateTime.format(new Date(iso)) : "—";
}
