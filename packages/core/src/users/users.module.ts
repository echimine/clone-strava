import { Module } from "@nestjs/common";
import { UserProfileRepository } from "./repositories/user-profile.repository.js";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import { UsersService } from "./users.service.js";

/** `users` module (ADR-021 §1, layer 0). Exports only its service. */
@Module({
  providers: [UserProfileRepository, GetUserSummariesUseCase, UsersService],
  exports: [UsersService],
})
export class UsersModule {}
