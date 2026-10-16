import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { AuthModule } from "../auth/auth.module.js";
import { ConfigModule } from "../config/config.module.js";
import { RealtimeGrantsController } from "./realtime-grants.controller.js";
import { RealtimeTokenController } from "./realtime-token.controller.js";

@Module({
  imports: [AuthModule, ConfigModule, ActivitiesModule],
  controllers: [RealtimeTokenController, RealtimeGrantsController],
})
export class RealtimeTokenModule {}
