import { Module } from "@nestjs/common";
import { SegmentsModule as CoreSegmentsModule } from "@repo/core/segments";

/**
 * Segments in `apps/api` (ADR-039 §12): one controller per spec, composed here. Also gives
 * `SegmentsService` to the `segments:import` script.
 */
@Module({
  imports: [CoreSegmentsModule],
  controllers: [],
})
export class SegmentsModule {}
