import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import { SEGMENTS_QUEUE_NAME } from "@repo/contracts";
import { ActivitiesModule } from "../activities/index.js";
import { SportsModule } from "../sports/index.js";
import { SegmentRepository } from "./repositories/segment.repository.js";
import { SegmentEffortRepository } from "./repositories/segment-effort.repository.js";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { SegmentsService } from "./segments.service.js";

/**
 * `segments` module (ADR-021 §1/§2: layer 3, may depend on `activities`,
 * `sports`). Registers the `segments` queue as a producer (ADR-011,
 * ADR-021 §5); only `apps/worker` registers a processor for it. Exports
 * only its service.
 */
@Module({
  imports: [ActivitiesModule, SportsModule, BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [SegmentRepository, SegmentEffortRepository, MatchSegmentsUseCase, SegmentsService],
  exports: [SegmentsService],
})
export class SegmentsModule {}
