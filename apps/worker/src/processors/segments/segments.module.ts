import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { SegmentsModule } from "@repo/core/segments";
import { SegmentMatchingScheduler } from "./segment-matching.scheduler.js";
import { SegmentsProcessor } from "./segments.processor.js";

@Module({
  imports: [SegmentsModule, BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [SegmentsProcessor],
})
export class SegmentsProcessorModule {}

/**
 * The `reconcile-segment-matching` schedule (ADR-039 §13), apart from the processor: the
 * integration tests run the sweep on demand, since a sweep started by another test file would
 * match their Activities without their in-memory traces.
 */
@Module({
  imports: [BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [SegmentMatchingScheduler],
})
export class SegmentMatchingSchedulerModule {}
