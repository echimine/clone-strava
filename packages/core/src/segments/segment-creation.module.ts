import { BullModule } from "@nestjs/bullmq";
import { Injectable, Module } from "@nestjs/common";
import {
  SEGMENTS_QUEUE_NAME,
  type CreatedSegment,
  type CreateSegmentRequest,
  type PreviewSegmentRequest,
  type SegmentPreview,
} from "@repo/contracts";
import { SegmentCreationRepository } from "./repositories/segment-creation.repository.js";
import { SegmentDuplicates } from "./services/segment-duplicates.js";
import { SegmentHistoryJobs } from "./services/segment-history-jobs.js";
import { SegmentMeasurementService } from "./services/segment-measurement.js";
import { CreateSegmentUseCase } from "./use-cases/create-segment.use-case.js";

/** Facade of the creation of a Segment by an athlete (spec #249, ADR-039 §5, §7). */
@Injectable()
export class SegmentCreationService {
  constructor(private readonly createSegment: CreateSegmentUseCase) {}

  /** `POST /v1/segments/preview`: nothing written. */
  preview(userId: string, request: PreviewSegmentRequest): Promise<SegmentPreview> {
    return this.createSegment.preview(userId, request);
  }

  /** `POST /v1/segments`: stars it and starts its retro-matching. */
  create(userId: string, request: CreateSegmentRequest): Promise<CreatedSegment> {
    return this.createSegment.create(userId, request);
  }
}

/**
 * The part of `segments` that draws new Segments, apart from `SegmentsModule` because it needs
 * the global `ElevationModule` (ADR-030 §4) and `AnalyticsModule`, which only `apps/api`
 * registers: `apps/worker` and the backoffice keep importing `SegmentsModule` alone.
 */
@Module({
  imports: [BullModule.registerQueue({ name: SEGMENTS_QUEUE_NAME })],
  providers: [
    SegmentCreationRepository,
    SegmentMeasurementService,
    SegmentDuplicates,
    SegmentHistoryJobs,
    CreateSegmentUseCase,
    SegmentCreationService,
  ],
  exports: [SegmentCreationService],
})
export class SegmentCreationModule {}
