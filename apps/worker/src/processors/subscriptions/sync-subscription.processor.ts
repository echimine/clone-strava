import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job } from "bullmq";
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
    if (!this.subscriptionsService.revenueCatConfigured) {
      // No retry can help: the job fails for good, visible on the backoffice's Jobs screen.
      throw new UnrecoverableError("RevenueCat non configuré");
    }
    this.logger.log({ userId: data.userId, requestId: data.requestId }, "Syncing subscription");

    // Re-reads the customer from RevenueCat's API v2 (never trusts the webhook body that
    // triggered this job) and writes the `premium` row as RevenueCat computes the entitlement,
    // inside `SubscriptionsService` (ADR-011, ADR-014, ADR-038 §12). A RevenueCat failure throws:
    // the job is retried.
    await this.subscriptionsService.sync(data.userId);
  }
}
