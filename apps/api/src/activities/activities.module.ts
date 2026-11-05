import { Module } from "@nestjs/common";
import { ActivitiesModule as CoreActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { ActivitiesController } from "./activities.controller.js";
import { ActivityMediaController } from "./activity-media.controller.js";
import { ActivityImportsController } from "./activity-imports.controller.js";
import { BestEffortsController } from "./best-efforts.controller.js";
import { CommentAssembler } from "./comment-assembler.js";
import { CommentsController } from "./comments.controller.js";
import { KudosAssembler } from "./kudos-assembler.js";
import { KudosController } from "./kudos.controller.js";

@Module({
  imports: [AuthModule, CoreActivitiesModule, EngagementModule, IdentitiesModule, ViewerFilterModule],
  controllers: [
    ActivitiesController,
    ActivityImportsController,
    ActivityMediaController,
    KudosController,
    CommentsController,
    BestEffortsController,
  ],
  // The detail reuses the feed's author and engagement assembly (ADR-033 §2).
  providers: [CommentAssembler, FeedAssembler, KudosAssembler, MediaAssembler],
})
export class ActivitiesModule {}
