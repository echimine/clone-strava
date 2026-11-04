import { Injectable, Logger } from "@nestjs/common";
import { RevenuecatEventRepository } from "../repositories/revenuecat-event.repository.js";
import { SyncJobEnqueuer } from "../services/sync-job-enqueuer.js";

/** A webhook delivery, as the API received it. */
export interface RevenueCatWebhookDelivery {
  /** RevenueCat's event id: deliveries are deduplicated on it. */
  id: string;
  type: string;
  /** The customer: our user id, set by the app's RevenueCat SDK. */
  appUserId: string;
  /** The whole body, stored for the user sheet's history (never shown raw). */
  payload: unknown;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Records the webhook event (deduplicated by id) and enqueues `sync-subscription` (ADR-014
 * "Backend side" steps 1-2, ADR-038 §12). Called by `apps/api`'s webhook controller; the worker
 * re-reads the authoritative state rather than trusting this body. An event for a customer that
 * is not one of our accounts (an anonymous RevenueCat id, a deleted account) is ignored.
 */
@Injectable()
export class HandleRevenuecatWebhookUseCase {
  private readonly logger = new Logger(HandleRevenuecatWebhookUseCase.name);

  constructor(
    private readonly revenuecatEvents: RevenuecatEventRepository,
    private readonly syncJobs: SyncJobEnqueuer,
  ) {}

  async execute(delivery: RevenueCatWebhookDelivery, requestId?: string): Promise<void> {
    if (!UUID.test(delivery.appUserId)) {
      this.logger.warn({ eventId: delivery.id, type: delivery.type }, "RevenueCat event for an unknown customer, ignored");
      return;
    }
    const recorded = await this.revenuecatEvents.record({
      id: delivery.id,
      userId: delivery.appUserId,
      type: delivery.type,
      payload: delivery.payload,
    });
    if (!recorded) {
      this.logger.log({ eventId: delivery.id, type: delivery.type }, "RevenueCat event already stored or unknown athlete");
      return;
    }
    await this.syncJobs.enqueue(delivery.appUserId, requestId);
  }
}
