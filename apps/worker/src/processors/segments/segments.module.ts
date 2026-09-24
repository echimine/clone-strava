import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { SegmentsModule } from "@repo/core/segments";
import { MatchSegmentsProcessor } from "./match-segments.processor.js";

@Module({
  imports: [SegmentsModule, BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [MatchSegmentsProcessor],
})
export class SegmentsProcessorModule {}
