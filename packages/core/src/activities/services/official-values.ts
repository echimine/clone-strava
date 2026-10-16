import { gunzipSync } from "node:zlib";
import { Injectable } from "@nestjs/common";
import { ACTIVITY_TRACE_MAX_BYTES, activityTraceKey, traceSchema, type Trace } from "@repo/contracts";
import type { schema } from "@repo/db";
import { simplifyTrack } from "@repo/geo";
import { GeocodingService } from "../../geocoding/index.js";
import type { DbExecutor } from "../../infrastructure/index.js";
import { ObjectTooLargeError, StorageService } from "../../storage/index.js";
import { UsersService } from "../../users/index.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { applyPrivacyZone } from "../domain/apply-privacy-zone.js";
import { cleanTrace, MAX_TRACE_ACCURACY_M, maxPlausibleSpeedMs } from "../domain/clean-trace.js";
import { computeMetrics } from "../domain/compute-metrics.js";
import { feedPolyline } from "../domain/feed-polyline.js";
import { computeHeartRate } from "../domain/heart-rate.js";
import { toLineStringEwkt, toPointEwkt } from "../domain/ewkt.js";

/** Douglas-Peucker tolerance of the stored route (ADR-019 §5 step 5). */
const ROUTE_TOLERANCE_M = 5;

/** The activity fields the official values depend on. */
export interface ActivityToCompute {
  id: string;
  userId: string;
  sportTypeCode: string;
}

/** Why a stored trace cannot be used: permanent, retrying will not help (ADR-019 §6). */
export type TraceProblem = "invalid_trace" | "empty_trace";

export type LoadedTrace = { trace: Trace } | { problem: TraceProblem };

/** The rows `process-activity` and `reprocess-activity` write, computed for one sport. */
export interface OfficialValues {
  stats: typeof schema.activityStats.$inferInsert;
  track: typeof schema.activityTrack.$inferInsert;
}

/**
 * The steps shared by `process-activity` and `reprocess-activity` (ADR-019 §5, ADR-033 §5):
 * read the stored trace, clean it with the sport's plausible speed, compute the metrics,
 * apply the privacy zone, build the route, polyline and place name, and write
 * `activity_stats` / `activity_track`.
 */
@Injectable()
export class OfficialValuesService {
  constructor(
    private readonly activityStats: ActivityStatsRepository,
    private readonly activityTracks: ActivityTrackRepository,
    private readonly users: UsersService,
    private readonly storage: StorageService,
    private readonly geocoding: GeocodingService,
  ) {}

  /** Downloads and validates the stored trace. Storage errors are thrown (technical, retried). */
  async loadTrace(activity: ActivityToCompute): Promise<LoadedTrace> {
    let compressed: Uint8Array | undefined;
    try {
      compressed = await this.storage.getObject(
        activityTraceKey(activity.userId, activity.id),
        ACTIVITY_TRACE_MAX_BYTES,
      );
    } catch (error) {
      if (error instanceof ObjectTooLargeError) {
        return { problem: "invalid_trace" };
      }
      throw error;
    }
    if (!compressed) {
      return { problem: "invalid_trace" };
    }

    let json: unknown;
    try {
      json = JSON.parse(gunzipSync(compressed).toString("utf8"));
    } catch {
      return { problem: "invalid_trace" };
    }
    const parsed = traceSchema.safeParse(json);
    if (!parsed.success) {
      return { problem: "invalid_trace" };
    }
    if (parsed.data.points.length === 0) {
      return { problem: "empty_trace" };
    }
    return { trace: parsed.data };
  }

  /**
   * The official values of `trace` for the activity's current sport, or `undefined` when fewer
   * than two points survive the cleanup. Geocoding is best effort and runs here, outside any
   * transaction.
   */
  async compute(activity: ActivityToCompute, trace: Trace): Promise<OfficialValues | undefined> {
    const points = cleanTrace(trace.points, {
      maxAccuracyM: MAX_TRACE_ACCURACY_M,
      maxSpeedMs: maxPlausibleSpeedMs(activity.sportTypeCode),
      pauses: trace.pauses,
    });
    if (points.length < 2) {
      return undefined;
    }

    const metrics = computeMetrics(points, { pauses: trace.pauses });
    const heartRate = computeHeartRate(points);
    const { privacyZoneRadiusM } = await this.users.getActivityDefaults(activity.userId);
    const shown = simplifyTrack(applyPrivacyZone(points, { radiusM: privacyZoneRadiusM }), ROUTE_TOLERANCE_M);
    // ADR-029: feed card data, from the privacy-zoned route only.
    const mapPolyline = feedPolyline(shown);
    const locationName = shown.length >= 2 ? await this.geocoding.reverse(shown[0]!) : null;

    return {
      stats: {
        activityId: activity.id,
        distanceM: metrics.distanceM,
        movingTimeS: Math.round(metrics.movingTimeS),
        elapsedTimeS: Math.round(metrics.elapsedTimeS),
        elevationGainM: metrics.elevationGainM,
        avgSpeedMs: metrics.avgSpeedMs,
        maxSpeedMs: metrics.maxSpeedMs,
        avgHeartRate: heartRate.avgHeartRate ?? null,
        maxHeartRate: heartRate.maxHeartRate ?? null,
        computedForSportTypeCode: activity.sportTypeCode,
      },
      track: {
        activityId: activity.id,
        // Nothing left outside the privacy zone: no route is shown to others.
        route: shown.length >= 2 ? toLineStringEwkt(shown) : null,
        startPoint: shown.length >= 2 ? toPointEwkt(shown[0]!) : null,
        rawPointsS3Key: activityTraceKey(activity.userId, activity.id),
        pointCount: points.length,
        mapPolyline,
        locationName,
      },
    };
  }

  /** Upserts `activity_stats` and `activity_track`, inside the caller's transaction. */
  async save(values: OfficialValues, tx: DbExecutor): Promise<void> {
    await this.activityStats.upsert(values.stats, tx);
    await this.activityTracks.upsert(values.track, tx);
  }
}
