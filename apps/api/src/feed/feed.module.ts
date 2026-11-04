import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { IdentitiesModule } from "../identities/identities.module.js";
import { FeedAssembler } from "./feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { FeedController } from "./feed.controller.js";

@Module({
  imports: [AuthModule, ActivitiesModule, EngagementModule, IdentitiesModule, ViewerFilterModule],
  controllers: [FeedController],
  providers: [FeedAssembler, MediaAssembler],
})
export class FeedModule {}
