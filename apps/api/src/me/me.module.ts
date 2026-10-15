import { Module } from "@nestjs/common";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { MeController } from "./me.controller.js";

@Module({
  imports: [AuthModule, SubscriptionsModule, UsersModule],
  controllers: [MeController],
})
export class MeModule {}
