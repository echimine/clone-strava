import type { TracePoint } from "./compute-metrics.js";

export interface PrivacyZoneOptions {
  /** `user_profile.privacy_zone_radius_m` (ADR-017). */
  radiusM: number;
}

/**
 * Removes the first and last `radiusM` meters of the route before it is
 * stored in `activity_track` (ADR-019 §5 step 6): the version shown to
 * others never reveals the exact start/end (typically home).
 *
 * TODO: real trimming (walk cumulative distance from each end, drop points
 * within `radiusM`, keep the raw trace untouched in the bucket). Left as a
 * stub for this skeleton; the signature is what
 * `process-activity.use-case.ts` and its tests depend on.
 */
export function applyPrivacyZone(
  _routePoints: TracePoint[],
  _options: PrivacyZoneOptions,
): TracePoint[] {
  throw new Error("not implemented");
}
