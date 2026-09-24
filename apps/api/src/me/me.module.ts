import { Module } from "@nestjs/common";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AuthModule } from "../auth/auth.module.js";
import { MeController } from "./me.controller.js";

@Module({
  imports: [AuthModule, SubscriptionsModule],
  controllers: [MeController],
})
export class MeModule {}
