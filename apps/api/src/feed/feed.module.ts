import { Module } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { UsersModule } from "@repo/core/users";
import { AuthModule } from "../auth/auth.module.js";
import { FeedAssembler } from "./feed-assembler.js";
import { FeedController } from "./feed.controller.js";

@Module({
  imports: [AuthModule, ActivitiesModule, EngagementModule, UsersModule],
  controllers: [FeedController],
  providers: [FeedAssembler],
})
export class FeedModule {}
