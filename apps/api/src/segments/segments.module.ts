import { Module } from "@nestjs/common";
import { SegmentCreationModule, SegmentsModule as CoreSegmentsModule } from "@repo/core/segments";
import { SocialModule } from "@repo/core/social";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { OpenDataController } from "./open-data.controller.js";
import { SegmentCreationController } from "./segment-creation.controller.js";
import { SegmentMapController } from "./segment-map.controller.js";
import { SegmentSheetController } from "./segment-sheet.controller.js";

/**
 * `/v1/segments` (ADR-039 §12): one controller per spec (#249 creation, #250 map, #251 sheet, #253
 * open data). Also gives `SegmentsService` to the `segments:import` script. `apps/api` composes
 * (ADR-039 §2): it resolves Premium (`subscriptions`), the viewer filter and the followees
 * (`social`), then passes them to `segments`.
 */
@Module({
  imports: [
    AuthModule,
    CoreSegmentsModule,
    SegmentCreationModule,
    IdentitiesModule,
    SocialModule,
    SubscriptionsModule,
    ViewerFilterModule,
  ],
  controllers: [SegmentCreationController, SegmentMapController, SegmentSheetController, OpenDataController],
})
export class SegmentsModule {}
