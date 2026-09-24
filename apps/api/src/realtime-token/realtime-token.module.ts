import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { ConfigModule } from "../config/config.module.js";
import { RealtimeTokenController } from "./realtime-token.controller.js";

@Module({
  imports: [AuthModule, ConfigModule],
  controllers: [RealtimeTokenController],
})
export class RealtimeTokenModule {}
