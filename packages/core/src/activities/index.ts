export { ActivitiesModule } from "./activities.module.js";
export { ActivitiesService } from "./activities.service.js";
export type { ActivityFailureCounts, ActivityGrowthCounts } from "./domain/activity-admin-stats.js";
export type { ActivityDetailRecord } from "./domain/activity-detail.js";
export type { ActivityRecord } from "./domain/activity-record.js";
export type {
  ActivityLabel,
  AdminActivityFilter,
  AdminActivityRecord,
  AdminActivityRow,
} from "./domain/admin-activity.js";
export type {
  FailedActivityRow,
  FailedImportRow,
  FailurePage,
  StaleActivityRow,
} from "./domain/admin-failure.js";
export type { ActivityTextReset } from "./use-cases/reset-activity-text.use-case.js";
export type { ActivityMediaRecord, GalleryMediaPage, GalleryMediaRecord } from "./domain/activity-media.js";
export type { FeedActivity, FeedActivityPage, FeedActivityStats } from "./domain/feed-activity.js";
export type { AthleteProfileFigures } from "./use-cases/get-athlete-profile-figures.use-case.js";
export type { ConfirmMediaResult } from "./use-cases/confirm-media.use-case.js";
export type { CreateActivityResult } from "./use-cases/create-activity.use-case.js";
export type { CreateActivityImportResult } from "./use-cases/create-activity-import.use-case.js";
export type { ImportActivityResult } from "./use-cases/import-activity-from-file.use-case.js";
export { PermanentProcessingError } from "./domain/processing-error.js";
export { ACTIVITY_ANALYSIS_VERSION } from "./domain/compute-analysis.js";
export type { BestEffortRecord } from "./domain/best-effort-record.js";
export { RECORD_DISTANCES_M, RECORD_SETS, type RecordSet } from "./domain/best-efforts.js";
export { MEDALS, type Medal } from "./domain/medals.js";
export { activityNotFound } from "./services/activity-not-found.js";
export {
  ATHLETE_TIME_ZONE,
  addDays,
  athleteLocalDate,
  athleteWeekStart,
  mondayOf,
  zeroFilledWeeks,
  type WeekTotals,
} from "./domain/athlete-weeks.js";
export { streakWeeks } from "./domain/streak.js";
export type {
  ActivitiesNearPathPage,
  ActivitiesNearPathQuery,
  ActivityMatchingTrace,
} from "./domain/matching-trace.js";
export type { ReprocessOutcome } from "./use-cases/reprocess-activity.use-case.js";
