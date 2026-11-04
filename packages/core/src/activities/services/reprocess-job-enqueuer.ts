import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  REPROCESS_ACTIVITY_JOB_NAME,
  recomputeActivityJobId,
  reprocessActivityJobId,
  reprocessAnalysisJobId,
  type ReprocessActivityJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY } from "../../infrastructure/index.js";

/**
 * Enqueues `reprocess-activity` (ADR-033 §5) under the job id of the Activity's last edit,
 * `reprocess-{activityId}-{updatedAt epoch ms}`, with the ADR-019 §6 retry policy. Shared by the
 * `PATCH` and the reconciliation sweep, so both produce the same id.
 */
@Injectable()
export class ReprocessJobEnqueuer {
  constructor(@InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ReprocessActivityJob>) {}

  /**
   * Added only if no job holds that id, whatever its state: a reprocessing that failed for good
   * keeps the old values (ADR-033 §5) instead of being retried by every sweep. A later edit
   * bumps `updated_at`, hence a new id and a new attempt. Returns whether a job was added.
   */
  enqueue(job: ReprocessActivityJob, updatedAt: Date): Promise<boolean> {
    return this.addOnce(job, reprocessActivityJobId(job.activityId, updatedAt));
  }

  /**
   * The analysis backfill (ADR-036 §7), `reprocess-{activityId}-analysis-v{version}`: one attempt
   * per analysis version, under the same rule.
   */
  enqueueForAnalysis(job: ReprocessActivityJob, analysisVersion: number): Promise<boolean> {
    return this.addOnce(job, reprocessAnalysisJobId(job.activityId, analysisVersion));
  }

  /**
   * « Recalculer » from the backoffice (ADR-038 §14): always added, under a new id
   * `reprocess-activity-{activityId}-{at epoch ms}`, since the id of the last edit still holds
   * the job that failed. Returns the job id.
   */
  async enqueueRecompute(job: ReprocessActivityJob, at: Date): Promise<string> {
    const jobId = recomputeActivityJobId(job.activityId, at);
    await this.queue.add(REPROCESS_ACTIVITY_JOB_NAME, job, { ...DEFAULT_JOB_RETRY, jobId });
    return jobId;
  }

  private async addOnce(job: ReprocessActivityJob, jobId: string): Promise<boolean> {
    if (await this.queue.getJob(jobId)) {
      return false;
    }
    await this.queue.add(REPROCESS_ACTIVITY_JOB_NAME, job, { ...DEFAULT_JOB_RETRY, jobId });
    return true;
  }
}
