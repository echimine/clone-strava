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
import { ActivityAnalysisRepository } from "../repositories/activity-analysis.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ACTIVITY_ANALYSIS_VERSION, EMPTY_ACTIVITY_ANALYSIS } from "../domain/compute-analysis.js";
import { PermanentProcessingError } from "../domain/processing-error.js";
import { OfficialValuesService, type OfficialValues } from "../services/official-values.js";

type ActivityRow = NonNullable<Awaited<ReturnType<ActivityRepository["findById"]>>>;

/**
 * `reprocess-activity` job logic (ADR-033 §5, ADR-036 §7): recompute a processed Activity's
 * official values from its stored trace, as `process-activity` does, and upsert
 * `activity_stats` / `activity_track` / `activity_analysis` in one transaction, when its sport
 * changed or its analysis is missing or outdated; otherwise a no-op. `processing_status` stays
 * `processed`. A failure leaves the old values (a permanent one is thrown as
 * {@link PermanentProcessingError}, never recorded as `failed`); an Activity without a usable
 * trace still gets an empty analysis, so the backfill does not pick it again. After the commit,
 * `activities.activity.updated` `["stats"]` only when the sport changed: the backfill stays
 * silent.
 */
@Injectable()
export class ReprocessActivityUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly analyses: ActivityAnalysisRepository,
    private readonly officialValues: OfficialValuesService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: ReprocessActivityJob): Promise<void> {
    const activity = await this.activities.findById(job.activityId);
    if (!activity || activity.processingStatus !== "processed") {
      // Deleted in between: nothing to recompute.
      return;
    }
    const [[stats], analysis] = await Promise.all([
      this.activityStats.findByActivityIds([activity.id]),
      this.analyses.findByActivityId(activity.id),
    ]);
    const sportChanged = stats?.computedForSportTypeCode !== activity.sportTypeCode;
    const analysisOutdated = !analysis || analysis.version < ACTIVITY_ANALYSIS_VERSION;
    if (!sportChanged && !analysisOutdated) {
      return;
    }

    const computed = await this.computeValues(activity);
    if ("problem" in computed) {
      if (analysisOutdated) {
        await this.saveEmptyAnalysis(activity.id);
      }
      if (!sportChanged || activity.source === "manual") {
        // Only the analysis was due, or no trace by design: the empty analysis is all there is.
        return;
      }
      // The old official values stay (ADR-033 §5).
      throw new PermanentProcessingError(
        computed.problem,
        `Activity ${activity.id} reprocessing: ${computed.problem}`,
      );
    }

    const values = computed.values;
    const saved = await this.db.transaction(async (tx) => {
      // A sport changed again (or a delete) since the read wins: its own job recomputes.
      const current = await this.activities.findForUpdate(activity.id, tx);
      if (current?.processingStatus !== "processed" || current.sportTypeCode !== activity.sportTypeCode) {
        return false;
      }
      await this.officialValues.save(values, tx);
      return true;
    });

    if (saved && sportChanged) {
      const event: ActivityUpdatedEvent = {
        activityId: activity.id,
        userId: activity.userId,
        changedFields: ["stats"],
      };
      this.events.emit(ACTIVITY_UPDATED_EVENT, event);
    }
  }

  /** The recomputed values, or why there are none: a manual entry or an unusable trace. */
  private async computeValues(
    activity: ActivityRow,
  ): Promise<{ values: OfficialValues } | { problem: "invalid_trace" | "empty_trace" }> {
    if (activity.source === "manual") {
      return { problem: "empty_trace" };
    }
    const loaded = await this.officialValues.loadTrace(activity);
    if ("problem" in loaded) {
      return loaded;
    }
    const values = await this.officialValues.compute(activity, loaded.trace);
    return values ? { values } : { problem: "empty_trace" };
  }

  /** ADR-036 §6: `splits: []`, `series: null`, so the backfill does not pick the Activity again. */
  private async saveEmptyAnalysis(activityId: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      const current = await this.activities.findForUpdate(activityId, tx);
      if (current?.processingStatus === "processed") {
        await this.officialValues.saveAnalysis(activityId, EMPTY_ACTIVITY_ANALYSIS, tx);
      }
    });
  }
}
