import { Module } from "@nestjs/common";
import { UsersModule } from "../users/index.js";
import { AthleteBlockRepository } from "./repositories/athlete-block.repository.js";
import { FollowSettingsRepository } from "./repositories/follow-settings.repository.js";
import { FollowRepository } from "./repositories/follow.repository.js";
import { FollowPageReader } from "./services/follow-page-reader.js";
import { FollowStateReader } from "./services/follow-state-reader.js";
import { FollowStatusesReader } from "./services/follow-statuses-reader.js";
import { AcceptFollowRequestUseCase } from "./use-cases/accept-follow-request.use-case.js";
import { BlockAthleteUseCase } from "./use-cases/block-athlete.use-case.js";
import { FollowAthleteUseCase } from "./use-cases/follow-athlete.use-case.js";
import { GetFolloweeIdsUseCase } from "./use-cases/get-followee-ids.use-case.js";
import { ListFollowRequestsUseCase } from "./use-cases/list-follow-requests.use-case.js";
import { ListFollowsUseCase } from "./use-cases/list-follows.use-case.js";
import { RefuseFollowRequestUseCase } from "./use-cases/refuse-follow-request.use-case.js";
import { RemoveFollowerUseCase } from "./use-cases/remove-follower.use-case.js";
import { UnblockAthleteUseCase } from "./use-cases/unblock-athlete.use-case.js";
import { UnfollowAthleteUseCase } from "./use-cases/unfollow-athlete.use-case.js";
import { UpdateFollowSettingsUseCase } from "./use-cases/update-follow-settings.use-case.js";
import { SocialService } from "./social.service.js";

/** `social` module (ADR-021 §1/§2: layer 1, may depend on `users`). Exports only its service. */
@Module({
  imports: [UsersModule],
  providers: [
    FollowRepository,
    FollowSettingsRepository,
    AthleteBlockRepository,
    BlockAthleteUseCase,
    UnblockAthleteUseCase,
    FollowStateReader,
    FollowStatusesReader,
    FollowPageReader,
    FollowAthleteUseCase,
    UnfollowAthleteUseCase,
    ListFollowsUseCase,
    ListFollowRequestsUseCase,
    AcceptFollowRequestUseCase,
    RefuseFollowRequestUseCase,
    RemoveFollowerUseCase,
    UpdateFollowSettingsUseCase,
    GetFolloweeIdsUseCase,
    SocialService,
  ],
  exports: [SocialService],
})
export class SocialModule {}
