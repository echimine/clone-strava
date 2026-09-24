import { Injectable, NotImplementedException } from "@nestjs/common";
import { RevenuecatEventRepository } from "../repositories/revenuecat-event.repository.js";

/**
 * Records the webhook event (deduplicated by id) and enqueues
 * `sync-subscription` (ADR-014 "Backend side" steps 1-2). Called by
 * `apps/api`'s webhook controller; the worker re-reads the authoritative
 * state rather than trusting this body.
 */
@Injectable()
export class HandleRevenuecatWebhookUseCase {
  constructor(private readonly revenuecatEvents: RevenuecatEventRepository) {}

  async execute(_eventId: string, _userId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
