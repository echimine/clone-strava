/** DI token of {@link AccountsProcessorOptions}. */
export const ACCOUNTS_PROCESSOR_OPTIONS = Symbol("ACCOUNTS_PROCESSOR_OPTIONS");

/**
 * PostHog for the `delete-account` job (ADR-038 §13); RevenueCat comes from the app's global
 * `RevenueCatModule`. A step whose keys are missing is skipped and logged, never failed.
 */
export interface AccountsProcessorOptions {
  /** PostHog private API: a personal key scoped `person:write`, the project id, the EU host. */
  postHog: { personalApiKey?: string; projectId?: string; host?: string };
  /** The HTTP client; tests pass a fake (never a real call). */
  fetch?: typeof fetch;
}

/** PostHog's private API on the EU cloud (ADR-015), not the ingestion host. */
export const POSTHOG_EU_API_HOST = "https://eu.posthog.com";
