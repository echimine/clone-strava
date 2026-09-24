import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { SUBSCRIPTIONS_QUEUE_NAME } from "@repo/contracts";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { SyncSubscriptionProcessor } from "./sync-subscription.processor.js";

@Module({
  imports: [SubscriptionsModule, BullModule.registerQueue({ name: SUBSCRIPTIONS_QUEUE_NAME })],
  providers: [SyncSubscriptionProcessor],
})
export class SubscriptionsProcessorModule {}
