import { Module } from "@nestjs/common";
import { SportsModule } from "@repo/core/sports";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { MeController } from "./me.controller.js";
import { OnboardingAnswersController } from "./onboarding-answers.controller.js";

@Module({
  imports: [AuthModule, SportsModule, SubscriptionsModule, UsersModule],
  controllers: [MeController, OnboardingAnswersController],
})
export class MeModule {}
