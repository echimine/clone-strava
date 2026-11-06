import { Module } from "@nestjs/common";
import { ItinerariesModule as CoreItinerariesModule } from "@repo/core/itineraries";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AuthModule } from "../auth/auth.module.js";
import { ItinerariesController } from "./itineraries.controller.js";

@Module({
  imports: [AuthModule, CoreItinerariesModule, SubscriptionsModule],
  controllers: [ItinerariesController],
})
export class ItinerariesModule {}
