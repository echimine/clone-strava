import { Inject, Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_UPDATED_EVENT,
  type ActivityUpdatedEvent,
  type ReprocessActivityJob,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { PermanentProcessingError } from "../domain/processing-error.js";
import { OfficialValuesService } from "../services/official-values.js";

/**
 * `reprocess-activity` job logic (ADR-033 §5): after a sport change, recompute a processed
 * Activity's official values from its stored trace, as `process-activity` does, and upsert
 * `activity_stats` / `activity_track` in one transaction. `processing_status` stays
 * `processed`; a no-op when the values were already computed for the current sport. A failure
 * leaves the old values (a permanent one is thrown as {@link PermanentProcessingError}, never
 * recorded as `failed`). On success, after the commit: `activities.activity.updated` `["stats"]`.
 */
@Injectable()
export class ReprocessActivityUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly officialValues: OfficialValuesService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: ReprocessActivityJob): Promise<void> {
    const activity = await this.activities.findById(job.activityId);
    if (!activity || activity.processingStatus !== "processed") {
      // Deleted in between: nothing to recompute.
      return;
    }
    const [stats] = await this.activityStats.findByActivityIds([activity.id]);
    if (stats?.computedForSportTypeCode === activity.sportTypeCode) {
      return;
    }

    const loaded = await this.officialValues.loadTrace(activity);
    if ("problem" in loaded) {
      throw new PermanentProcessingError(
        loaded.problem,
        `Activity ${activity.id} reprocessing: ${loaded.problem}`,
      );
    }
    const values = await this.officialValues.compute(activity, loaded.trace);
    if (!values) {
      throw new PermanentProcessingError("empty_trace", `Activity ${activity.id} reprocessing: empty_trace`);
    }

    const saved = await this.db.transaction(async (tx) => {
      // A sport changed again (or a delete) since the read wins: its own job recomputes.
      const current = await this.activities.findForUpdate(activity.id, tx);
      if (current?.processingStatus !== "processed" || current.sportTypeCode !== activity.sportTypeCode) {
        return false;
      }
      await this.officialValues.save(values, tx);
      return true;
    });

    if (saved) {
      const event: ActivityUpdatedEvent = {
        activityId: activity.id,
        userId: activity.userId,
        changedFields: ["stats"],
      };
      this.events.emit(ACTIVITY_UPDATED_EVENT, event);
    }
  }
}
