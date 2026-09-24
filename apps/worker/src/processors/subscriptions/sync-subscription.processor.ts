import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import type { Job } from "bullmq";
import {
  SUBSCRIPTIONS_QUEUE_NAME,
  SYNC_SUBSCRIPTION_JOB_NAME,
  syncSubscriptionJobSchema,
} from "@repo/contracts";
import { SubscriptionsService } from "@repo/core/subscriptions";

@Processor(SUBSCRIPTIONS_QUEUE_NAME, { concurrency: 10 })
export class SyncSubscriptionProcessor extends WorkerHost {
  private readonly logger = new Logger(SyncSubscriptionProcessor.name);

  constructor(private readonly subscriptionsService: SubscriptionsService) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== SYNC_SUBSCRIPTION_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${SUBSCRIPTIONS_QUEUE_NAME}": ${job.name}`);
      return;
    }

    const data = syncSubscriptionJobSchema.parse(job.data);
    this.logger.log({ userId: data.userId }, "Syncing subscription");

    // Re-reads the full subscriber state from the RevenueCat REST API
    // (never trusts the webhook body that triggered this job), updates the
    // premium status in the database, sends the `subscription_*` PostHog
    // event -- all inside `SubscriptionsService` (ADR-011, ADR-014).
    await this.subscriptionsService.sync(data.userId);
  }
}
