import { InjectQueue, OnWorkerEvent, Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job, type Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  MATCH_SEGMENTS_JOB_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  SEGMENTS_QUEUE_NAME,
  matchSegmentsJobId,
  processActivityJobSchema,
} from "@repo/contracts";
import { ActivitiesService, PermanentProcessingError } from "@repo/core/activities";

/**
 * Job name for the recurring reconciliation sweep (ADR-019 §7).
 * Worker-internal: job chaining and scheduling live in `apps/worker`, never
 * in a `packages/core` module (ADR-021 §2 rule 2).
 */
export const RECONCILE_ACTIVITIES_JOB_NAME = "reconcile-activities";
/** Every 10 minutes (ADR-019 §7). */
export const RECONCILE_ACTIVITIES_REPEAT_MS = 10 * 60 * 1000;

@Processor(ACTIVITIES_QUEUE_NAME, { concurrency: 5 })
export class ProcessActivityProcessor extends WorkerHost {
  private readonly logger = new Logger(ProcessActivityProcessor.name);

  constructor(
    @InjectQueue(SEGMENTS_QUEUE_NAME) private readonly segmentsQueue: Queue,
    private readonly activitiesService: ActivitiesService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    switch (job.name) {
      case PROCESS_ACTIVITY_JOB_NAME:
        await this.processActivity(job);
        return;
      case RECONCILE_ACTIVITIES_JOB_NAME:
        await this.reconcile();
        return;
      default:
        this.logger.warn(`Unknown job name on queue "${ACTIVITIES_QUEUE_NAME}": ${job.name}`);
    }
  }

  private async processActivity(job: Job): Promise<void> {
    const data = processActivityJobSchema.parse(job.data);
    this.logger.log(
      { activityId: data.activityId, requestId: data.requestId },
      "Processing activity",
    );

    // Reads the activity + profile + sport type, downloads and validates
    // the trace, cleans it up, computes metrics, builds the route, applies
    // the privacy zone, upserts activity_stats / activity_track in a
    // transaction, moves the activity to `processed`, then emits the
    // domain event `activities.activity.processed` (or `.failed` on a
    // permanent failure) after commit -- all inside `ActivitiesService`
    // (ADR-003, ADR-011 §5, ADR-019 §5). The realtime bridge forwards it to
    // the mobile app; this processor never publishes to Redis directly
    // (ADR-021 §4).
    try {
      await this.activitiesService.process(data);
    } catch (error) {
      // Invalid trace: already recorded as `failed`, no retry (ADR-019 §6).
      if (error instanceof PermanentProcessingError) {
        throw new UnrecoverableError(error.message);
      }
      throw error;
    }

    // Job chaining is the worker's responsibility, not a module's (ADR-021
    // §2 rule 2): enqueue `match-segments` right after a successful
    // `process-activity`, with a deterministic job id (ADR-019 §8).
    await this.segmentsQueue.add(
      MATCH_SEGMENTS_JOB_NAME,
      { activityId: data.activityId, userId: data.userId, requestId: data.requestId },
      { jobId: matchSegmentsJobId(data.activityId) },
    );
  }

  /** Last technical attempt failed: the activity becomes `failed` / `processing_error` (ADR-019 §6). */
  @OnWorkerEvent("failed")
  async onFailed(job: Job | undefined, error: Error): Promise<void> {
    if (!job || job.name !== PROCESS_ACTIVITY_JOB_NAME || error.name === "UnrecoverableError") {
      return;
    }
    if (job.attemptsMade < (job.opts.attempts ?? 1)) {
      return;
    }
    const data = processActivityJobSchema.safeParse(job.data);
    if (!data.success) {
      return;
    }
    try {
      await this.activitiesService.markProcessingFailed(data.data);
    } catch (markError) {
      this.logger.error(`Could not mark activity ${data.data.activityId} as failed: ${String(markError)}`);
    }
  }

  private async reconcile(): Promise<void> {
    // Re-enqueues `process-activity` for activities, and `import-activity`
    // for imports (ADR-028 §8), left `processing` for more than 15 minutes
    // without a live job (ADR-019 §7): covers a failed enqueue, a lost job,
    // or a loss of Redis data (ADR-018 §7).
    const count = await this.activitiesService.reconcileStuck();
    this.logger.log(`Reconciliation sweep: ${count} activity(ies) re-enqueued`);
  }
}
