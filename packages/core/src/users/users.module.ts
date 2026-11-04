import { Module } from "@nestjs/common";
import { UserProfileRepository } from "./repositories/user-profile.repository.js";
import { UserSportRepository } from "./repositories/user-sport.repository.js";
import { CopyGoogleAvatarUseCase } from "./use-cases/copy-google-avatar.use-case.js";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import { RemoveAvatarUseCase } from "./use-cases/remove-avatar.use-case.js";
import { RequestAvatarUploadUseCase } from "./use-cases/request-avatar-upload.use-case.js";
import { SearchUsersByNameUseCase } from "./use-cases/search-users-by-name.use-case.js";
import { SetAvatarUseCase } from "./use-cases/set-avatar.use-case.js";
import { SubmitOnboardingAnswersUseCase } from "./use-cases/submit-onboarding-answers.use-case.js";
import { SweepAvatarsUseCase } from "./use-cases/sweep-avatars.use-case.js";
import { UsersService } from "./users.service.js";

/** `users` module (ADR-021 §1, layer 0). Exports only its service. */
@Module({
  providers: [
    UserProfileRepository,
    UserSportRepository,
    GetUserSummariesUseCase,
    SubmitOnboardingAnswersUseCase,
    SearchUsersByNameUseCase,
    RequestAvatarUploadUseCase,
    SetAvatarUseCase,
    RemoveAvatarUseCase,
    SweepAvatarsUseCase,
    CopyGoogleAvatarUseCase,
    UsersService,
  ],
  exports: [UsersService],
})
export class UsersModule {}
