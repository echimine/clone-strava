export { SegmentsModule } from "./segments.module.js";
export { SegmentCreationModule, SegmentCreationService } from "./segment-creation.module.js";
export { SegmentsService, RECONCILE_SEGMENT_MATCHING_BATCH } from "./segments.service.js";
export type { ActivityEffortRecord } from "./domain/activity-effort.js";
export type {
  LeaderboardReader,
  LeaderboardRequest,
  LeaderboardView,
  LocalLegendView,
} from "./use-cases/get-segment-leaderboard.use-case.js";
export type { LeaderboardLine } from "./repositories/leaderboard.repository.js";
export type { SegmentSheetView, SheetEffort } from "./use-cases/get-segment-sheet.use-case.js";
export type { NervoImportReport } from "./use-cases/import-nervo-segments.use-case.js";
export type { ActivitySegmentResults, EffortMedalCount, EffortResult } from "./domain/effort-result.js";
export type { MapSegmentRecord, MapSegmentSearch } from "./repositories/segment-map.repository.js";
// Pure matching, reused to create Segments and by the Nervo generator (ADR-039 §5, §10).
export {
  isSameSegment,
  matchSegment,
  resampleSegmentPath,
  SEGMENT_MATCHING_THRESHOLDS,
  SEGMENT_MATCHING_VERSION,
  type MatchedEffort,
  type MatchingPause,
  type MatchingPoint,
  type MatchingTrace,
  type SegmentMatchingThresholds,
} from "./domain/match-segment.js";
export { replaySegmentMedals, type EffortStatus, type Medal, type MedalEffort } from "./domain/segment-medals.js";
export { MAX_EFFORT_SPEED_KMH } from "./domain/effort-sync.js";
export { DEFAULT_PRIVACY_ZONE_RADIUS_M, SEGMENT_SPORTS } from "./domain/segment-sports.js";
// Pure, shared with the Nervo generator (ADR-039 §5, §10).
export { climbCategory, type ClimbCategory } from "./domain/climb-category.js";
export {
  SEGMENT_CREATIONS_PER_DAY,
  SEGMENT_MAX_LENGTH_M,
  SEGMENT_MIN_ENDS_APART_M,
  SEGMENT_MIN_LENGTH_M,
  segmentFigures,
  segmentRuleViolations,
  resampleSegmentTrack,
  type SegmentFigures,
  type SegmentRuleViolation,
} from "./domain/segment-geometry.js";
