import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, Logger, type OnModuleInit } from "@nestjs/common";
import type { Queue } from "bullmq";
import { BUCKET_SWEEP_JOB_NAME, BUCKET_SWEEP_QUEUE_NAME } from "./bucket-sweep.processor.js";

/** Every day at 03:00 UTC, a quiet hour. */
export const BUCKET_SWEEP_CRON = "0 3 * * *";

/**
 * Registers the daily `bucket-sweep` (ADR-037 §11) the way the reconciliation is registered:
 * `upsertJobScheduler` is idempotent on its id, so a worker restart or a second instance never
 * adds a schedule. A cron pattern rather than `every`, so a restart does not run a sweep at once.
 */
@Injectable()
export class BucketSweepScheduler implements OnModuleInit {
  private readonly logger = new Logger(BucketSweepScheduler.name);

  constructor(@InjectQueue(BUCKET_SWEEP_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.upsertJobScheduler(
      BUCKET_SWEEP_JOB_NAME,
      { pattern: BUCKET_SWEEP_CRON, tz: "UTC" },
      { name: BUCKET_SWEEP_JOB_NAME },
    );
    this.logger.log("Bucket sweep scheduled every day at 03:00 UTC");
  }
}
