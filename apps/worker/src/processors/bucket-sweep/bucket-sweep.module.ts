import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { BUCKET_SWEEP_QUEUE_NAME } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { UsersModule } from "@repo/core/users";
import { BucketSweepProcessor } from "./bucket-sweep.processor.js";
import { BucketSweepScheduler } from "./bucket-sweep.scheduler.js";

/**
 * The daily `bucket-sweep` (ADR-037 §11). It composes `activities` and `users`, each sweeping
 * its own prefixes, so it lives here rather than in either module's processor.
 */
@Module({
  imports: [ActivitiesModule, UsersModule, BullModule.registerQueue({ name: BUCKET_SWEEP_QUEUE_NAME })],
  providers: [BucketSweepProcessor, BucketSweepScheduler],
})
export class BucketSweepProcessorModule {}
