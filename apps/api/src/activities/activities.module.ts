import { Module } from "@nestjs/common";
import { ActivitiesModule as CoreActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { AuthModule } from "../auth/auth.module.js";
import { ActivitiesController } from "./activities.controller.js";
import { ActivityImportsController } from "./activity-imports.controller.js";
import { KudosController } from "./kudos.controller.js";

@Module({
  imports: [AuthModule, CoreActivitiesModule, EngagementModule],
  controllers: [ActivitiesController, ActivityImportsController, KudosController],
})
export class ActivitiesModule {}
