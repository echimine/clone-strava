/** DI token of {@link AccountsProcessorOptions}. */
export const ACCOUNTS_PROCESSOR_OPTIONS = Symbol("ACCOUNTS_PROCESSOR_OPTIONS");

/**
 * The third parties the `delete-account` job cleans (ADR-038 §13). A step whose keys are missing
 * is skipped and logged, never failed.
 */
export interface AccountsProcessorOptions {
  /** RevenueCat API v2: a secret key (`sk_…`) and the project id. */
  revenueCat: { apiKey?: string; projectId?: string };
  /** PostHog private API: a personal key scoped `person:write`, the project id, the EU host. */
  postHog: { personalApiKey?: string; projectId?: string; host?: string };
  /** The HTTP client; tests pass a fake (never a real call). */
  fetch?: typeof fetch;
}

/** PostHog's private API on the EU cloud (ADR-015), not the ingestion host. */
export const POSTHOG_EU_API_HOST = "https://eu.posthog.com";
export const REVENUECAT_API_HOST = "https://api.revenuecat.com";
