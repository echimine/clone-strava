import { Injectable, NotImplementedException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_FAILED_EVENT,
  ACTIVITY_PROCESSED_EVENT,
  type ProcessActivityJob,
} from "@repo/contracts";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { computeMetrics } from "../domain/compute-metrics.js";
import { applyPrivacyZone } from "../domain/apply-privacy-zone.js";

/**
 * `process-activity` job logic (ADR-011, ADR-019 §5): read the activity,
 * profile and sport type; validate and clean the trace; `computeMetrics`;
 * `applyPrivacyZone`; upsert `activity_stats`/`activity_track` and move to
 * `processed` in a single transaction; then, after the commit, emit the
 * domain event (ADR-021 §3-4: never inside the transaction). Unreadable or
 * empty traces are a permanent failure (`UnrecoverableError`, thrown by the
 * `apps/worker` processor around this use case, ADR-019 §6).
 */
@Injectable()
export class ProcessActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly activityTracks: ActivityTrackRepository,
    private readonly events: EventEmitter2,
  ) {}

  async execute(_job: ProcessActivityJob): Promise<void> {
    throw new NotImplementedException();
    // Sketch (ADR-019 §5, ADR-021 §3-4), left as a comment since none of
    // the steps below are implemented yet:
    // 1. read activity + user_profile + sport_type
    // 2. download + validate trace, clean points
    // 3. const metrics = computeMetrics(points)
    // 4. const track = applyPrivacyZone(points, { radiusM: profile.privacyZoneRadiusM })
    // 5. transaction: activityStats.upsert(...), activityTracks.upsert(...), activities.updateStatus(id, "processed")
    // 6. after commit: this.events.emit(ACTIVITY_PROCESSED_EVENT, { activityId, userId, status: "processed", requestId })
    //    on permanent failure instead: this.events.emit(ACTIVITY_FAILED_EVENT, { activityId, userId, status: "failed", requestId })
  }
}
