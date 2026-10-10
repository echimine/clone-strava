import { Module } from "@nestjs/common";
import { ItinerariesModule as CoreItinerariesModule } from "@repo/core/itineraries";
import { AuthModule } from "../auth/auth.module.js";
import { ItinerariesController } from "./itineraries.controller.js";

@Module({
  imports: [AuthModule, CoreItinerariesModule],
  controllers: [ItinerariesController],
})
export class ItinerariesModule {}
