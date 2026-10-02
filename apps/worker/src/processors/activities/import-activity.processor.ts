import { InjectQueue, OnWorkerEvent, Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job, type Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  IMPORT_ACTIVITY_JOB_NAME,
  IMPORTS_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  importActivityJobSchema,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { ActivitiesService, PermanentProcessingError } from "@repo/core/activities";
import { enqueueUnique } from "@repo/core/infrastructure";

/**
 * `import-activity` (ADR-028 §4) on its own `imports` queue, concurrency 2:
 * parsing is CPU-bound and a burst of imports must never delay the
 * processing of activities recorded live (`activities` queue).
 */
@Processor(IMPORTS_QUEUE_NAME, { concurrency: 2 })
export class ImportActivityProcessor extends WorkerHost {
  private readonly logger = new Logger(ImportActivityProcessor.name);

  constructor(
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly activitiesQueue: Queue<ProcessActivityJob>,
    private readonly activitiesService: ActivitiesService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== IMPORT_ACTIVITY_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${IMPORTS_QUEUE_NAME}": ${job.name}`);
      return;
    }
    const data = importActivityJobSchema.parse(job.data);
    this.logger.log({ importId: data.importId, requestId: data.requestId }, "Importing activity file");

    let result;
    try {
      result = await this.activitiesService.importFromFile(data);
    } catch (error) {
      // Invalid file: already recorded as `failed`, no retry (ADR-028 §7).
      if (error instanceof PermanentProcessingError) {
        throw new UnrecoverableError(error.message);
      }
      throw error;
    }

    this.logger.log({ importId: data.importId, outcome: result.outcome }, "Activity file import done");
    if (result.outcome === "imported") {
      // Job chaining is the worker's responsibility (ADR-021 §2 rule 2): the
      // new activity follows ADR-019 §5-8 unchanged. A lost enqueue is
      // caught by the reconciliation sweep (ADR-019 §7).
      await enqueueUnique(
        this.activitiesQueue,
        PROCESS_ACTIVITY_JOB_NAME,
        { activityId: result.activityId, userId: data.userId, requestId: data.requestId },
        processActivityJobId(result.activityId),
      );
    }
  }

  /** Last technical attempt failed: the import becomes `failed` / `processing_error` (ADR-028 §7). */
  @OnWorkerEvent("failed")
  async onFailed(job: Job | undefined, error: Error): Promise<void> {
    if (!job || error instanceof UnrecoverableError || error.name === "UnrecoverableError") {
      return;
    }
    if (job.attemptsMade < (job.opts.attempts ?? 1)) {
      return;
    }
    const data = importActivityJobSchema.safeParse(job.data);
    if (!data.success) {
      return;
    }
    try {
      await this.activitiesService.markImportFailed(data.data);
    } catch (markError) {
      this.logger.error(`Could not mark import ${data.data.importId} as failed: ${String(markError)}`);
    }
  }
}
