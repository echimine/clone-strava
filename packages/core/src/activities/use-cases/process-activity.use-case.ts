import { Inject, Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_FAILED_EVENT,
  ACTIVITY_PROCESSED_EVENT,
  ANALYTICS_EVENTS,
  type ActivityFailedEvent,
  type ActivityProcessedEvent,
  type ProcessActivityJob,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { AnalyticsService } from "../../analytics/index.js";
import { DATABASE } from "../../infrastructure/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { PermanentProcessingError } from "../domain/processing-error.js";
import { OfficialValuesService } from "../services/official-values.js";

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
    private readonly officialValues: OfficialValuesService,
    private readonly analytics: AnalyticsService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: ProcessActivityJob): Promise<void> {
    const activity = await this.activities.findById(job.activityId);
    if (!activity || activity.processingStatus !== "processing") {
      // Deleted, already processed or failed: a replayed job is a no-op.
      return;
    }
    await this.activities.incrementAttempts(activity.id);

    const loaded = await this.officialValues.loadTrace(activity);
    if ("problem" in loaded) {
      return this.fail(activity, loaded.problem, job);
    }
    const values = await this.officialValues.compute(activity, loaded.trace);
    if (!values) {
      return this.fail(activity, "empty_trace", job);
    }

    await this.db.transaction(async (tx) => {
      await this.officialValues.save(values, tx);
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
