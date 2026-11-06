import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, Logger, type OnModuleInit } from "@nestjs/common";
import type { Queue } from "bullmq";
import { SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { JOB_RETENTION } from "@repo/core/infrastructure";
import {
  RECONCILE_SEGMENT_MATCHING_JOB_NAME,
  RECONCILE_SEGMENT_MATCHING_REPEAT_MS,
} from "./segments.processor.js";

/**
 * Registers `reconcile-segment-matching` every 10 minutes (ADR-039 §13), idempotent on its
 * scheduler id across restarts and instances, kept no longer than any other job (ADR-038 §14).
 */
@Injectable()
export class SegmentMatchingScheduler implements OnModuleInit {
  private readonly logger = new Logger(SegmentMatchingScheduler.name);

  constructor(@InjectQueue(SEGMENTS_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.upsertJobScheduler(
      RECONCILE_SEGMENT_MATCHING_JOB_NAME,
      { every: RECONCILE_SEGMENT_MATCHING_REPEAT_MS },
      { name: RECONCILE_SEGMENT_MATCHING_JOB_NAME, opts: JOB_RETENTION },
    );
    this.logger.log("Segment matching sweep scheduled every 10 minutes");
  }
}
