import { Module } from "@nestjs/common";
import { ActivitiesModule as CoreActivitiesModule } from "@repo/core/activities";
import { AuthModule } from "../auth/auth.module.js";
import { ActivitiesController } from "./activities.controller.js";

@Module({
  imports: [AuthModule, CoreActivitiesModule],
  controllers: [ActivitiesController],
})
export class ActivitiesModule {}
