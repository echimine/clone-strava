import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { ConfigModule } from "../config/config.module.js";
import { LiveParticipantTokenController } from "./live-participant-token.controller.js";

/** The Live SDK's Participant token (live.echimine.fr). */
@Module({
  imports: [AuthModule, ConfigModule],
  controllers: [LiveParticipantTokenController],
})
export class LiveModule {}
