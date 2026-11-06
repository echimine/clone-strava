import { Injectable } from "@nestjs/common";
import { cleanTrace, MAX_TRACE_ACCURACY_M, maxPlausibleSpeedMs } from "../domain/clean-trace.js";
import type { ActivityMatchingTrace } from "../domain/matching-trace.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { OfficialValuesService } from "../services/official-values.js";

/**
 * The matching trace of an Activity (ADR-039 §2, §6): its stored trace cleaned with its sport's
 * plausible speed, as for its official values, before the privacy zone. `null` for an Activity
 * that is gone or not processed. Storage errors are thrown (technical, retried by the job).
 */
@Injectable()
export class GetMatchingTraceUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly officialValues: OfficialValuesService,
  ) {}

  async execute(activityId: string): Promise<ActivityMatchingTrace | null> {
    const activity = await this.activities.findById(activityId);
    if (!activity || activity.processingStatus !== "processed") {
      return null;
    }
    const base = {
      activityId: activity.id,
      userId: activity.userId,
      sportTypeCode: activity.sportTypeCode,
      visibility: activity.visibility,
    };
    const loaded = activity.source === "manual" ? undefined : await this.officialValues.loadTrace(activity);
    if (!loaded || "problem" in loaded) {
      return { ...base, points: [], pauses: [], firstPoint: null, lastPoint: null };
    }
    const points = cleanTrace(loaded.trace.points, {
      maxAccuracyM: MAX_TRACE_ACCURACY_M,
      maxSpeedMs: maxPlausibleSpeedMs(activity.sportTypeCode),
      pauses: loaded.trace.pauses,
    }).map(({ lat, lon, timestampMs }) => ({ lat, lon, timestampMs }));
    const first = points[0];
    const last = points.at(-1);
    return {
      ...base,
      points,
      pauses: loaded.trace.pauses,
      firstPoint: first ? { lat: first.lat, lon: first.lon } : null,
      lastPoint: last ? { lat: last.lat, lon: last.lon } : null,
    };
  }
}
