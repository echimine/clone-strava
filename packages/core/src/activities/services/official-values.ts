import { gunzipSync } from "node:zlib";
import { Injectable } from "@nestjs/common";
import {
  ACTIVITY_TRACE_MAX_BYTES,
  activityTraceKey,
  traceSchema,
  type ActivityAnalysis,
  type Trace,
} from "@repo/contracts";
import type { schema } from "@repo/db";
import { simplifyTrack } from "@repo/geo";
import { GeocodingService } from "../../geocoding/index.js";
import type { DbExecutor } from "../../infrastructure/index.js";
import { ObjectTooLargeError, StorageService } from "../../storage/index.js";
import { UsersService } from "../../users/index.js";
import { ActivityAnalysisRepository } from "../repositories/activity-analysis.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { applyPrivacyZone } from "../domain/apply-privacy-zone.js";
import { cleanTrace, MAX_TRACE_ACCURACY_M, maxPlausibleSpeedMs } from "../domain/clean-trace.js";
import { recordSetOf } from "../domain/best-efforts.js";
import { ACTIVITY_ANALYSIS_VERSION, computeAnalysis } from "../domain/compute-analysis.js";
import { computeMetrics } from "../domain/compute-metrics.js";
import { feedPolyline } from "../domain/feed-polyline.js";
import { computeHeartRate } from "../domain/heart-rate.js";
import { toLineStringEwkt, toPointEwkt } from "../domain/ewkt.js";
import { BestEffortWriter, type ComputedBestEfforts } from "./best-effort-writer.js";

/** Douglas-Peucker tolerance of the stored route (ADR-019 §5 step 5). */
const ROUTE_TOLERANCE_M = 5;

/** The activity fields the official values depend on. */
export interface ActivityToCompute {
  id: string;
  userId: string;
  sportTypeCode: string;
  /** Copied onto the Best efforts: their Medals are replayed in this order (ADR-039 §8). */
  startedAt: Date;
}

export interface ComputeOptions {
  /**
   * Reverse geocode the start point (default). `false` when only the analysis lags: the stored
   * place name is kept, Mapbox is not called again (ADR-039 §3).
   */
  geocode?: boolean;
}

/** Why a stored trace cannot be used: permanent, retrying will not help (ADR-019 §6). */
export type TraceProblem = "invalid_trace" | "empty_trace";

export type LoadedTrace = { trace: Trace } | { problem: TraceProblem };

/** The rows `process-activity` and `reprocess-activity` write, computed for one sport. */
export interface OfficialValues {
  stats: typeof schema.activityStats.$inferInsert;
  track: typeof schema.activityTrack.$inferInsert;
  /** Splits and series (ADR-036 §6), from the cleaned trace before the privacy zone. */
  analysis: ActivityAnalysis;
  /** Best efforts over the sport's Record distances (ADR-039 §3), same trace as the analysis. */
  bestEfforts: ComputedBestEfforts;
}

/**
 * The steps shared by `process-activity` and `reprocess-activity` (ADR-019 §5, ADR-033 §5):
 * read the stored trace, clean it with the sport's plausible speed, compute the metrics,
 * apply the privacy zone, build the route, polyline and place name, and write
 * `activity_stats` / `activity_track` / `activity_analysis` (ADR-036 §6) and the Best efforts
 * with their Medals (ADR-039 §3).
 */
@Injectable()
export class OfficialValuesService {
  constructor(
    private readonly activityStats: ActivityStatsRepository,
    private readonly activityTracks: ActivityTrackRepository,
    private readonly activityAnalyses: ActivityAnalysisRepository,
    private readonly users: UsersService,
    private readonly storage: StorageService,
    private readonly geocoding: GeocodingService,
    private readonly bestEfforts: BestEffortWriter,
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
   * transaction; without it (`geocode: false`) `locationName` is left out and the stored one stays.
   */
  async compute(
    activity: ActivityToCompute,
    trace: Trace,
    { geocode = true }: ComputeOptions = {},
  ): Promise<OfficialValues | undefined> {
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
    // ADR-036 §6: no coordinates in it, so the untrimmed points reveal nothing the zone hides.
    // ADR-039 §3: the Best efforts too, on elapsed time, Pauses included.
    const recordSet = recordSetOf(activity.sportTypeCode);
    const { bestEfforts, ...analysis } = computeAnalysis(points, { pauses: trace.pauses, recordSet });
    const { privacyZoneRadiusM } = await this.users.getActivityDefaults(activity.userId);
    const zoned = applyPrivacyZone(points, { radiusM: privacyZoneRadiusM });
    const shown = simplifyTrack(zoned, ROUTE_TOLERANCE_M);
    // ADR-029: feed card data, from the privacy-zoned route only.
    const mapPolyline = feedPolyline(shown);
    const locationName = !geocode
      ? undefined
      : shown.length >= 2
        ? await this.geocoding.reverse(shown[0]!)
        : null;

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
        // ADR-036 §5: the card says "Départ et arrivée masqués".
        routeTrimmed: zoned.length < points.length,
        mapPolyline,
        locationName,
      },
      analysis,
      bestEfforts: {
        activityId: activity.id,
        userId: activity.userId,
        activityStartedAt: activity.startedAt,
        recordSet,
        efforts: bestEfforts,
      },
    };
  }

  /**
   * Upserts `activity_stats`, `activity_track`, `activity_analysis` and the Best efforts, then
   * replays the athlete's Medals they touch, inside the caller's transaction.
   */
  async save(values: OfficialValues, tx: DbExecutor): Promise<void> {
    await this.activityStats.upsert(values.stats, tx);
    await this.activityTracks.upsert(values.track, tx);
    await this.saveAnalysis(values.stats.activityId, values.analysis, tx);
    await this.bestEfforts.save(values.bestEfforts, tx);
  }

  /**
   * Upserts the analysis alone, at the current {@link ACTIVITY_ANALYSIS_VERSION}: an Activity
   * without a usable GPS trace gets `splits: []`, `series: null` so the backfill skips it
   * (ADR-036 §6-7).
   */
  async saveAnalysis(activityId: string, analysis: ActivityAnalysis, tx: DbExecutor): Promise<void> {
    await this.activityAnalyses.upsert(activityId, ACTIVITY_ANALYSIS_VERSION, analysis, tx);
  }
}
