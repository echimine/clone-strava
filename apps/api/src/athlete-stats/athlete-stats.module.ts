import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { AthleteStatsController } from "./stats.controller.js";

/** `GET /v1/me/progress` and `GET /v1/athletes/:id/stats` (ADR-036 §4). */
@Module({
  imports: [AuthModule, ActivitiesModule, IdentitiesModule, ViewerFilterModule],
  controllers: [AthleteStatsController],
})
export class AthleteStatsModule {}
