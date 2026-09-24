import { Module } from "@nestjs/common";
import { UsersModule } from "../users/index.js";
import { FollowRepository } from "./repositories/follow.repository.js";
import { FollowUserUseCase } from "./use-cases/follow-user.use-case.js";
import { GetFolloweeIdsUseCase } from "./use-cases/get-followee-ids.use-case.js";
import { SocialService } from "./social.service.js";

/** `social` module (ADR-021 §1/§2: layer 1, may depend on `users`). Exports only its service. */
@Module({
  imports: [UsersModule],
  providers: [FollowRepository, FollowUserUseCase, GetFolloweeIdsUseCase, SocialService],
  exports: [SocialService],
})
export class SocialModule {}
