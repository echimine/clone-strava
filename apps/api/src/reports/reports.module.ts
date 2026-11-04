import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { ModerationModule } from "@repo/core/moderation";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { ReportTargetReader } from "./report-target-reader.js";
import { ReportsController } from "./reports.controller.js";

/**
 * Reports (ADR-038 §9): the target is read through `activities`, `engagement`, `users` and `auth`
 * here, then recorded by `moderation` (layer 0, which reads no other module).
 */
@Module({
  imports: [
    AuthModule,
    ActivitiesModule,
    EngagementModule,
    UsersModule,
    ModerationModule,
    IdentitiesModule,
    ViewerFilterModule,
  ],
  controllers: [ReportsController],
  providers: [ReportTargetReader],
})
export class ReportsModule {}
