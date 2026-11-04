/**
 * Where each "À traiter" tile leads (ADR-038 §15). A tile shows its number without a link while
 * its screen does not exist: the moderation queue (#213), Jobs (#216, also for failed Activities
 * and imports) and the Efforts to review (#219) set their path here when they ship.
 */
export const TODO_LINKS: Record<
  "openReports" | "failedActivities" | "failedImports" | "failedJobs" | "suspiciousEfforts",
  string | undefined
> = {
  openReports: undefined,
  failedActivities: undefined,
  failedImports: undefined,
  failedJobs: undefined,
  suspiciousEfforts: undefined,
};

/** App usage stays in PostHog (ADR-015, ADR-038 §15): Nervo's EU project. */
export const POSTHOG_PROJECT_URL = "https://eu.posthog.com/project/300692";
