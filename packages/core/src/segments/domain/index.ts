/**
 * Pure part of `segments`, without Nest nor Drizzle (`@repo/core/segments/domain`): for tools
 * outside the apps, such as the Nervo generator (ADR-039 §10), which must not load the module.
 */
export { climbCategory, type ClimbCategory } from "./climb-category.js";
export {
  SEGMENT_MAX_LENGTH_M,
  SEGMENT_MIN_ENDS_APART_M,
  SEGMENT_MIN_LENGTH_M,
} from "./segment-geometry.js";
export {
  isSameSegment,
  matchSegment,
  resampleSegmentPath,
  SEGMENT_MATCHING_THRESHOLDS,
  SEGMENT_MATCHING_VERSION,
} from "./match-segment.js";
