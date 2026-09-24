import { Module } from "@nestjs/common";
import { ActivitiesModule } from "../activities/index.js";
import { SocialModule } from "../social/index.js";
import { UsersModule } from "../users/index.js";
import { KudosRepository } from "./repositories/kudos.repository.js";
import { CommentRepository } from "./repositories/comment.repository.js";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { AddCommentUseCase } from "./use-cases/add-comment.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import { EngagementService } from "./engagement.service.js";

/**
 * `engagement` module (ADR-021 §1/§2: layer 3, may depend on `activities`,
 * `social`, `users`). Exports only its service.
 */
@Module({
  imports: [ActivitiesModule, SocialModule, UsersModule],
  providers: [
    KudosRepository,
    CommentRepository,
    GiveKudosUseCase,
    AddCommentUseCase,
    GetEngagementCountsUseCase,
    EngagementService,
  ],
  exports: [EngagementService],
})
export class EngagementModule {}
