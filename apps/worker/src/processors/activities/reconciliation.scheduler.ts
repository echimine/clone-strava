import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, Logger, type OnModuleInit } from "@nestjs/common";
import type { Queue } from "bullmq";
import { ACTIVITIES_QUEUE_NAME } from "@repo/contracts";
import {
  RECONCILE_ACTIVITIES_JOB_NAME,
  RECONCILE_ACTIVITIES_REPEAT_MS,
} from "./process-activity.processor.js";

/**
 * Registers the recurring reconciliation job as a BullMQ repeatable job
 * (ADR-019 §7). `jobId` makes registration idempotent across worker
 * restarts and multiple instances: BullMQ keeps a single repeatable
 * schedule per `(name, jobId)` pair.
 */
@Injectable()
export class ReconciliationScheduler implements OnModuleInit {
  private readonly logger = new Logger(ReconciliationScheduler.name);

  constructor(@InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    // BullMQ v6 repeatable jobs go through a "job scheduler" rather than the
    // `repeat` option on `.add()` (removed in v6). `upsertJobScheduler` is
    // idempotent on `schedulerId`, so re-registering on every worker
    // restart or from multiple instances never creates duplicate schedules.
    await this.queue.upsertJobScheduler(
      RECONCILE_ACTIVITIES_JOB_NAME,
      { every: RECONCILE_ACTIVITIES_REPEAT_MS },
      { name: RECONCILE_ACTIVITIES_JOB_NAME },
    );
    this.logger.log("Reconciliation sweep scheduled every 10 minutes");
  }
}
