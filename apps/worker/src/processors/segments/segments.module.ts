import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { SegmentsModule } from "@repo/core/segments";
import { OpenDataExportScheduler } from "./open-data-export.scheduler.js";
import { SegmentMatchingScheduler } from "./segment-matching.scheduler.js";
import { SegmentsProcessor } from "./segments.processor.js";

@Module({
  imports: [SegmentsModule, BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [SegmentsProcessor],
})
export class SegmentsProcessorModule {}

/**
 * The `reconcile-segment-matching` and `export-segments-odbl` schedules (ADR-039 §13), apart from
 * the processor: the integration tests run them on demand, since a sweep started by another test
 * file would match their Activities without their in-memory traces.
 */
@Module({
  imports: [BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [SegmentMatchingScheduler, OpenDataExportScheduler],
})
export class SegmentMatchingSchedulerModule {}
