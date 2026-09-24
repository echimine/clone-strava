import { createHash, timingSafeEqual } from "node:crypto";
import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  UnauthorizedException,
} from "@nestjs/common";
import { createZodDto } from "nestjs-zod";
import { revenueCatWebhookBodySchema } from "@repo/contracts";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { CONFIG, type ApiEnv } from "../config/env.js";

/** Constant-time comparison; hashing first gives both buffers the same length. */
function secretMatches(received: string | undefined, expected: string): boolean {
  if (received === undefined) return false;
  const digest = (value: string) => createHash("sha256").update(value).digest();
  return timingSafeEqual(digest(received), digest(expected));
}

class RevenueCatWebhookBodyDto extends createZodDto(revenueCatWebhookBodySchema) {}

/**
 * `POST /v1/webhooks/revenuecat` (ADR-009 §5, ADR-014): outside any user
 * session, authenticated by a secret header configured in RevenueCat.
 */
@Controller("webhooks/revenuecat")
export class RevenueCatWebhookController {
  constructor(
    @Inject(CONFIG) private readonly config: ApiEnv,
    private readonly subscriptionsService: SubscriptionsService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async handle(
    @Headers("authorization") authorization: string | undefined,
    @Body() body: RevenueCatWebhookBodyDto,
  ): Promise<{ received: true }> {
    if (!secretMatches(authorization, this.config.REVENUECAT_WEBHOOK_SECRET)) {
      throw new UnauthorizedException();
    }

    // ADR-014: dedupe by `body.event.id` (`revenuecat_event` table),
    // enqueue `sync-subscription`. `app_user_id` is RevenueCat's identifier
    // for the subscriber, set by the mobile SDK to our own user id. The
    // worker re-reads the authoritative state from the RevenueCat REST API
    // rather than trusting this body.
    await this.subscriptionsService.handleWebhook(body.event.id, body.event.app_user_id);
    return { received: true };
  }
}
