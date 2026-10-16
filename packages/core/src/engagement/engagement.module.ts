import { Module } from "@nestjs/common";
import { ActivitiesModule } from "../activities/index.js";
import { SocialModule } from "../social/index.js";
import { UsersModule } from "../users/index.js";
import { KudosRepository } from "./repositories/kudos.repository.js";
import { CommentRepository } from "./repositories/comment.repository.js";
import { CommentEvents } from "./services/comment-events.service.js";
import { CommentableActivity } from "./services/commentable-activity.service.js";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { ListKudosUseCase } from "./use-cases/list-kudos.use-case.js";
import { AddCommentUseCase } from "./use-cases/add-comment.use-case.js";
import { ListCommentsUseCase } from "./use-cases/list-comments.use-case.js";
import { GetCommentUseCase } from "./use-cases/get-comment.use-case.js";
import { EditCommentUseCase } from "./use-cases/edit-comment.use-case.js";
import { DeleteCommentUseCase } from "./use-cases/delete-comment.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import { EngagementService } from "./engagement.service.js";

/**
 * `engagement` module (ADR-021 §1/§2: layer 3, may depend on `activities`,
 * `social`, `users`). Needs the global `EventEmitterModule` registered by
 * the app. Exports only its service.
 */
@Module({
  imports: [ActivitiesModule, SocialModule, UsersModule],
  providers: [
    KudosRepository,
    CommentRepository,
    CommentEvents,
    CommentableActivity,
    GiveKudosUseCase,
    ListKudosUseCase,
    AddCommentUseCase,
    ListCommentsUseCase,
    GetCommentUseCase,
    EditCommentUseCase,
    DeleteCommentUseCase,
    GetEngagementCountsUseCase,
    EngagementService,
  ],
  exports: [EngagementService],
})
export class EngagementModule {}
