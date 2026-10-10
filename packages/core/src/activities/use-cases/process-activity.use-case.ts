import { gunzipSync } from "node:zlib";
import { Inject, Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_FAILED_EVENT,
  ACTIVITY_PROCESSED_EVENT,
  ANALYTICS_EVENTS,
  activityTraceKey,
  traceSchema,
  type ActivityFailedEvent,
  type ActivityProcessedEvent,
  type ProcessActivityJob,
  type Trace,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { simplifyTrack } from "@repo/geo";
import { AnalyticsService } from "../../analytics/index.js";
import { GeocodingService } from "../../geocoding/index.js";
import { DATABASE } from "../../infrastructure/index.js";
import { ObjectTooLargeError, StorageService } from "../../storage/index.js";
import { UsersService } from "../../users/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { computeMetrics } from "../domain/compute-metrics.js";
import { applyPrivacyZone } from "../domain/apply-privacy-zone.js";
import { cleanTrace, maxPlausibleSpeedMs } from "../domain/clean-trace.js";
import { feedPolyline } from "../domain/feed-polyline.js";
import { computeHeartRate } from "../domain/heart-rate.js";
import { PermanentProcessingError } from "../domain/processing-error.js";
import { toLineStringEwkt, toPointEwkt } from "../domain/ewkt.js";

/** Compressed traces above this size are refused (several hours at 1 Hz stay far below). */
const MAX_TRACE_BYTES = 50 * 1024 * 1024;
/** ADR-019 §5 step 3: GPS fixes less accurate than this are dropped. */
const MAX_ACCURACY_M = 50;
/** Douglas-Peucker tolerance of the stored route (ADR-019 §5 step 5). */
const ROUTE_TOLERANCE_M = 5;

/**
 * `process-activity` job logic (ADR-011, ADR-019 §5): read the activity
 * and profile; download, validate and clean the trace; compute metrics;
 * build the route and apply the privacy zone; upsert `activity_stats` /
 * `activity_track` and move to `processed` in one transaction; then,
 * after the commit, emit the domain event (ADR-021 §3-4). Invalid traces
 * are recorded as `failed` and rethrown as {@link PermanentProcessingError}
 * (the processor turns it into `UnrecoverableError`, ADR-019 §6).
 */
@Injectable()
export class ProcessActivityUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly activityTracks: ActivityTrackRepository,
    private readonly users: UsersService,
    private readonly storage: StorageService,
    private readonly analytics: AnalyticsService,
    private readonly geocoding: GeocodingService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: ProcessActivityJob): Promise<void> {
    const activity = await this.activities.findById(job.activityId);
    if (!activity || activity.processingStatus !== "processing") {
      // Deleted, already processed or failed: a replayed job is a no-op.
      return;
    }
    await this.activities.incrementAttempts(activity.id);

    const trace = await this.readTrace(activity, job);
    const points = cleanTrace(trace.points, {
      maxAccuracyM: MAX_ACCURACY_M,
      maxSpeedMs: maxPlausibleSpeedMs(activity.sportTypeCode),
    });
    if (points.length < 2) {
      return this.fail(activity, "empty_trace", job);
    }

    const metrics = computeMetrics(points);
    const heartRate = computeHeartRate(points);
    const { privacyZoneRadiusM } = await this.users.getActivityDefaults(activity.userId);
    const shown = simplifyTrack(applyPrivacyZone(points, { radiusM: privacyZoneRadiusM }), ROUTE_TOLERANCE_M);
    // ADR-029: feed card data, from the privacy-zoned route only. Geocoding is
    // best effort and stays outside the transaction.
    const mapPolyline = feedPolyline(shown);
    const locationName = shown.length >= 2 ? await this.geocoding.reverse(shown[0]!) : null;

    await this.db.transaction(async (tx) => {
      await this.activityStats.upsert(
        {
          activityId: activity.id,
          distanceM: metrics.distanceM,
          movingTimeS: Math.round(metrics.movingTimeS),
          elapsedTimeS: Math.round(metrics.elapsedTimeS),
          elevationGainM: metrics.elevationGainM,
          avgSpeedMs: metrics.avgSpeedMs,
          maxSpeedMs: metrics.maxSpeedMs,
          avgHeartRate: heartRate.avgHeartRate ?? null,
          maxHeartRate: heartRate.maxHeartRate ?? null,
        },
        tx,
      );
      await this.activityTracks.upsert(
        {
          activityId: activity.id,
          // Nothing left outside the privacy zone: no route is shown to others.
          route: shown.length >= 2 ? toLineStringEwkt(shown) : null,
          startPoint: shown.length >= 2 ? toPointEwkt(shown[0]!) : null,
          rawPointsS3Key: activityTraceKey(activity.userId, activity.id),
          pointCount: points.length,
          mapPolyline,
          locationName,
        },
        tx,
      );
      await this.activities.markProcessed(activity.id, tx);
    });

    const event: ActivityProcessedEvent = {
      activityId: activity.id,
      userId: activity.userId,
      status: "processed",
      requestId: job.requestId,
    };
    this.events.emit(ACTIVITY_PROCESSED_EVENT, event);
    this.analytics.capture(ANALYTICS_EVENTS.ACTIVITY_PROCESSED, activity.userId, {
      sportTypeCode: activity.sportTypeCode,
    });
  }

  /** Technical retries exhausted (ADR-019 §6): called by the worker on the last failed attempt. */
  async markTechnicalFailure(job: ProcessActivityJob): Promise<void> {
    const activity = await this.activities.findById(job.activityId);
    if (activity?.processingStatus === "processing") {
      await this.recordFailure(activity, "processing_error", job);
    }
  }

  private async readTrace(
    activity: { id: string; userId: string; sportTypeCode: string },
    job: ProcessActivityJob,
  ): Promise<Trace> {
    let compressed: Uint8Array | undefined;
    try {
      compressed = await this.storage.getObject(
        activityTraceKey(activity.userId, activity.id),
        MAX_TRACE_BYTES,
      );
    } catch (error) {
      if (error instanceof ObjectTooLargeError) {
        return this.fail(activity, "invalid_trace", job);
      }
      throw error;
    }
    if (!compressed) {
      return this.fail(activity, "invalid_trace", job);
    }

    let json: unknown;
    try {
      json = JSON.parse(gunzipSync(compressed).toString("utf8"));
    } catch {
      return this.fail(activity, "invalid_trace", job);
    }
    const parsed = traceSchema.safeParse(json);
    if (!parsed.success) {
      return this.fail(activity, "invalid_trace", job);
    }
    if (parsed.data.points.length === 0) {
      return this.fail(activity, "empty_trace", job);
    }
    return parsed.data;
  }

  private async fail(
    activity: { id: string; userId: string; sportTypeCode: string },
    code: string,
    job: ProcessActivityJob,
  ): Promise<never> {
    await this.recordFailure(activity, code, job);
    throw new PermanentProcessingError(code, `Activity ${activity.id} failed: ${code}`);
  }

  private async recordFailure(
    activity: { id: string; userId: string; sportTypeCode: string },
    code: string,
    job: ProcessActivityJob,
  ): Promise<void> {
    await this.activities.markFailed(activity.id, code);
    const event: ActivityFailedEvent = {
      activityId: activity.id,
      userId: activity.userId,
      status: "failed",
      requestId: job.requestId,
    };
    this.events.emit(ACTIVITY_FAILED_EVENT, event);
    this.analytics.capture(ANALYTICS_EVENTS.ACTIVITY_FAILED, activity.userId, {
      sportTypeCode: activity.sportTypeCode,
      errorCode: code,
    });
  }
}
