import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import { SUBSCRIPTIONS_QUEUE_NAME } from "@repo/contracts";
import { UserSubscriptionRepository } from "./repositories/user-subscription.repository.js";
import { RevenuecatEventRepository } from "./repositories/revenuecat-event.repository.js";
import { HandleRevenuecatWebhookUseCase } from "./use-cases/handle-revenuecat-webhook.use-case.js";
import { SyncSubscriptionUseCase } from "./use-cases/sync-subscription.use-case.js";
import { SubscriptionsService } from "./subscriptions.service.js";

/**
 * `subscriptions` module (ADR-021 §1, layer 0). Registers the
 * `subscriptions` queue as a producer (ADR-011, ADR-021 §5); only
 * `apps/worker` registers a processor for it. Exports only its service.
 */
@Module({
  imports: [BullModule.registerQueue({ name: SUBSCRIPTIONS_QUEUE_NAME })],
  providers: [
    UserSubscriptionRepository,
    RevenuecatEventRepository,
    HandleRevenuecatWebhookUseCase,
    SyncSubscriptionUseCase,
    SubscriptionsService,
  ],
  exports: [SubscriptionsService],
})
export class SubscriptionsModule {}
