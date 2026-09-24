import { Injectable, NotImplementedException } from "@nestjs/common";
import { UserSubscriptionRepository } from "../repositories/user-subscription.repository.js";

/**
 * `sync-subscription` job logic (ADR-014, ADR-011): re-reads the full
 * subscriber state from the RevenueCat REST API and upserts
 * `user_subscription`. Called by `apps/worker`'s processor, never enqueues
 * itself.
 */
@Injectable()
export class SyncSubscriptionUseCase {
  constructor(private readonly userSubscriptions: UserSubscriptionRepository) {}

  async execute(_userId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
