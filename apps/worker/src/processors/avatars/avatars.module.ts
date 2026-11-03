import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { AVATARS_QUEUE_NAME } from "@repo/contracts";
import { UsersModule } from "@repo/core/users";
import { CopyGoogleAvatarProcessor } from "./copy-google-avatar.processor.js";

/** The `avatars` queue (ADR-037 §2): the copy of the Google photo, enqueued by `auth`. */
@Module({
  imports: [UsersModule, BullModule.registerQueue({ name: AVATARS_QUEUE_NAME })],
  providers: [CopyGoogleAvatarProcessor],
})
export class AvatarsProcessorModule {}
