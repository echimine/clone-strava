import { Module } from "@nestjs/common";
import { ActivitiesModule as CoreActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { ActivitiesController } from "./activities.controller.js";
import { ActivityImportsController } from "./activity-imports.controller.js";
import { CommentAssembler } from "./comment-assembler.js";
import { CommentsController } from "./comments.controller.js";
import { KudosController } from "./kudos.controller.js";

@Module({
  imports: [AuthModule, CoreActivitiesModule, EngagementModule, UsersModule],
  controllers: [ActivitiesController, ActivityImportsController, KudosController, CommentsController],
  // The detail reuses the feed's author and engagement assembly (ADR-033 §2).
  providers: [CommentAssembler, FeedAssembler],
})
export class ActivitiesModule {}
