import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  SUBSCRIPTIONS_QUEUE_NAME,
  SYNC_SUBSCRIPTION_JOB_NAME,
  syncSubscriptionJobId,
  type SyncSubscriptionJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";

/**
 * Enqueues `sync-subscription` under its deterministic id (ADR-011 §2) with the default retry
 * policy. A job still waiting reads RevenueCat when it runs, so a second one is not needed.
 */
@Injectable()
export class SyncJobEnqueuer {
  constructor(@InjectQueue(SUBSCRIPTIONS_QUEUE_NAME) private readonly queue: Queue<SyncSubscriptionJob>) {}

  enqueue(userId: string, requestId?: string): Promise<boolean> {
    return enqueueUnique(
      this.queue,
      SYNC_SUBSCRIPTION_JOB_NAME,
      { userId, ...(requestId ? { requestId } : {}) },
      syncSubscriptionJobId(userId),
    );
  }
}
