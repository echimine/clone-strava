import { Module } from "@nestjs/common";
import { SocialModule } from "@repo/core/social";
import { SportsModule } from "@repo/core/sports";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { MeController } from "./me.controller.js";
import { OnboardingAnswersController } from "./onboarding-answers.controller.js";
import { SportsActiveCatalog } from "./sports-active-catalog.js";

@Module({
  imports: [AuthModule, SocialModule, SportsModule, SubscriptionsModule, UsersModule],
  controllers: [MeController, OnboardingAnswersController],
  providers: [SportsActiveCatalog],
})
export class MeModule {}
