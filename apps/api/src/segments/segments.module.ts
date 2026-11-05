import { Module } from "@nestjs/common";
import { SegmentCreationModule, SegmentsModule as CoreSegmentsModule } from "@repo/core/segments";
import { AuthModule } from "../auth/auth.module.js";
import { SegmentCreationController } from "./segment-creation.controller.js";

/** `/v1/segments*` (ADR-039 §12): one controller per spec. */
@Module({
  imports: [AuthModule, CoreSegmentsModule, SegmentCreationModule],
  controllers: [SegmentCreationController],
})
export class SegmentsModule {}
