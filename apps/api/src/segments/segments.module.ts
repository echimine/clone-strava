import { Module } from "@nestjs/common";
import { SegmentsModule as CoreSegmentsModule } from "@repo/core/segments";
import { SocialModule } from "@repo/core/social";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { SegmentSheetController } from "./segment-sheet.controller.js";

/**
 * `/v1/segments` (ADR-039 §12). `apps/api` composes (ADR-039 §2): it resolves Premium
 * (`subscriptions`), the viewer filter and the followees (`social`), then passes them to
 * `segments`. One controller per spec.
 */
@Module({
  imports: [AuthModule, CoreSegmentsModule, IdentitiesModule, SocialModule, SubscriptionsModule, ViewerFilterModule],
  controllers: [SegmentSheetController],
})
export class SegmentsModule {}
