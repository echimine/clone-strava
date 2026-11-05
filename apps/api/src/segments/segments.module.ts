import { Module } from "@nestjs/common";
import { SegmentsModule as CoreSegmentsModule } from "@repo/core/segments";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { SegmentCreationController } from "./segment-creation.controller.js";
import { SegmentMapController } from "./segment-map.controller.js";

/** `/v1/segments` (ADR-039 §12): one controller per spec (#249 creation, #250 map, #251 sheet, #253 open data). */
@Module({
  imports: [AuthModule, CoreSegmentsModule, ViewerFilterModule],
  controllers: [SegmentCreationController, SegmentMapController],
})
export class SegmentsModule {}
