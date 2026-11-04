/**
 * Where each "À traiter" tile leads (ADR-038 §15). A tile shows its number without a link while
 * its screen does not exist: the Efforts to review (#219) set their path here when they ship.
 * Open Reports open the moderation queue (#213); failed Activities and imports the Jobs screen's
 * "Échecs" tab, failed jobs its "Files" tab (#216).
 */
export const TODO_LINKS: Record<
  "openReports" | "failedActivities" | "failedImports" | "failedJobs" | "suspiciousEfforts",
  string | undefined
> = {
  openReports: "/reports",
  failedActivities: "/jobs",
  failedImports: "/jobs",
  failedJobs: "/jobs?tab=files",
  suspiciousEfforts: undefined,
};

/** App usage stays in PostHog (ADR-015, ADR-038 §15): Nervo's EU project. */
export const POSTHOG_PROJECT_URL = "https://eu.posthog.com/project/300692";
