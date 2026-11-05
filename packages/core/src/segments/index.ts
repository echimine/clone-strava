export { SegmentsModule } from "./segments.module.js";
export { SegmentsService, RECONCILE_SEGMENT_MATCHING_BATCH } from "./segments.service.js";
export type { ActivityEffortRecord } from "./domain/activity-effort.js";
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
