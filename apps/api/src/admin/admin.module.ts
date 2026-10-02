import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { AuthModule } from "../auth/auth.module.js";
import { AdminController } from "./admin.controller.js";

@Module({
  imports: [AuthModule, ActivitiesModule],
  controllers: [AdminController],
})
export class AdminModule {}
