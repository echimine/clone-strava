import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import { SUBSCRIPTIONS_QUEUE_NAME } from "@repo/contracts";
import { PremiumAdminStatsRepository } from "./repositories/premium-admin-stats.repository.js";
import { UserSubscriptionRepository } from "./repositories/user-subscription.repository.js";
import { RevenuecatEventRepository } from "./repositories/revenuecat-event.repository.js";
import { RevenueCatClient } from "./services/revenuecat-client.js";
import { SyncJobEnqueuer } from "./services/sync-job-enqueuer.js";
import { PromotionalPremiumUseCase } from "./use-cases/promotional-premium.use-case.js";
import { HandleRevenuecatWebhookUseCase } from "./use-cases/handle-revenuecat-webhook.use-case.js";
import { SyncSubscriptionUseCase } from "./use-cases/sync-subscription.use-case.js";
import { SubscriptionsService } from "./subscriptions.service.js";

/**
 * `subscriptions` module (ADR-021 §1, layer 0). Registers the
 * `subscriptions` queue as a producer (ADR-011, ADR-021 §5); only
 * `apps/worker` registers a processor for it. Exports only its service. RevenueCat's API v2 is
 * configured once per app with `RevenueCatModule.forRoot` (ADR-038 §12).
 */
@Module({
  imports: [BullModule.registerQueue({ name: SUBSCRIPTIONS_QUEUE_NAME })],
  providers: [
    PremiumAdminStatsRepository,
    UserSubscriptionRepository,
    RevenuecatEventRepository,
    RevenueCatClient,
    SyncJobEnqueuer,
    HandleRevenuecatWebhookUseCase,
    SyncSubscriptionUseCase,
    PromotionalPremiumUseCase,
    SubscriptionsService,
  ],
  exports: [SubscriptionsService],
})
export class SubscriptionsModule {}
