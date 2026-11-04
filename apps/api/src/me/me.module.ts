import { Module } from "@nestjs/common";
import { SocialModule } from "@repo/core/social";
import { SportsModule } from "@repo/core/sports";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { UsersModule } from "@repo/core/users";
import { AccountDeletionModule } from "../account-deletion/account-deletion.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { MeAccountDeletionController } from "./me-account-deletion.controller.js";
import { MeAvatarController } from "./me-avatar.controller.js";
import { MeController } from "./me.controller.js";
import { OnboardingAnswersController } from "./onboarding-answers.controller.js";
import { SportsActiveCatalog } from "./sports-active-catalog.js";

@Module({
  imports: [AccountDeletionModule, AuthModule, IdentitiesModule, SocialModule, SportsModule, SubscriptionsModule, UsersModule],
  controllers: [MeController, MeAccountDeletionController, MeAvatarController, OnboardingAnswersController],
  providers: [SportsActiveCatalog],
})
export class MeModule {}
