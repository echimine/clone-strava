import { InjectQueue } from "@nestjs/bullmq";
import { Injectable, Logger, type OnModuleInit } from "@nestjs/common";
import type { Queue } from "bullmq";
import { EXPORT_SEGMENTS_ODBL_JOB_NAME, SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { JOB_RETENTION } from "@repo/core/infrastructure";

/** Every Monday at 04:00 UTC, a quiet hour, after the daily bucket sweep. */
export const EXPORT_SEGMENTS_ODBL_CRON = "0 4 * * 1";

/**
 * Registers the weekly `export-segments-odbl` (ADR-039 §13), idempotent on its scheduler id, a
 * cron pattern so that a restart does not export at once.
 */
@Injectable()
export class OpenDataExportScheduler implements OnModuleInit {
  private readonly logger = new Logger(OpenDataExportScheduler.name);

  constructor(@InjectQueue(SEGMENTS_QUEUE_NAME) private readonly queue: Queue) {}

  async onModuleInit(): Promise<void> {
    await this.queue.upsertJobScheduler(
      EXPORT_SEGMENTS_ODBL_JOB_NAME,
      { pattern: EXPORT_SEGMENTS_ODBL_CRON, tz: "UTC" },
      { name: EXPORT_SEGMENTS_ODBL_JOB_NAME, opts: JOB_RETENTION },
    );
    this.logger.log("ODbL export of the Segments scheduled every Monday at 04:00 UTC");
  }
}
