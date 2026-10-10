import type express from "express";
import {
  BadRequestException,
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Req,
  UnauthorizedException,
} from "@nestjs/common";
import { createZodDto } from "nestjs-zod";
import { resendWebhookBodySchema } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { NotificationsService, type ResendWebhookHeaders } from "@repo/core/notifications";

class ResendWebhookBodyDto extends createZodDto(resendWebhookBodySchema) {}

type RawBodyRequest = express.Request & { rawBody?: Buffer };

/**
 * `POST /v1/webhooks/resend` (ADR-023): outside any user session,
 * authenticated by a Svix HMAC signature over the raw request body
 * (`NotificationsService.verifyWebhookSignature`, never the SDK directly --
 * ADR-021 §6 module boundary). `jsonBodyParser` tees the pre-parse buffer onto
 * `req.rawBody` for this route alone, since Svix verification needs the
 * exact bytes Resend signed, not the re-serialized parsed body.
 *
 * Subscribed events (Resend dashboard): `email.bounced`, `email.complained`
 * flag the recipient's email as unverified; `email.delivery_delayed` is
 * logged only. Any other event type, and any event whose signature or
 * `data.to` is missing/invalid, is acked with `{ received: true }` rather
 * than erroring -- webhook endpoints must not make Resend retry an event
 * they cannot or should not act on.
 */
@Controller("webhooks/resend")
export class ResendWebhookController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly authService: AuthService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async handle(
    @Req() request: RawBodyRequest,
    @Headers("svix-id") svixId: string | undefined,
    @Headers("svix-timestamp") svixTimestamp: string | undefined,
    @Headers("svix-signature") svixSignature: string | undefined,
    @Body() body: ResendWebhookBodyDto,
  ): Promise<{ received: true }> {
    if (request.rawBody === undefined) {
      // Should never happen given the scoped `express.json` `verify`
      // callback in `jsonBodyParser` -- fail loudly rather than silently skip
      // signature verification.
      throw new BadRequestException("Missing raw body for webhook signature verification");
    }
    if (svixId === undefined || svixTimestamp === undefined || svixSignature === undefined) {
      throw new BadRequestException("Missing Svix signature headers");
    }

    // `verifyWebhookSignature` takes the raw body as a `string` (not
    // `Buffer`) and expects plain `id`/`timestamp`/`signature` keys, not
    // the raw `svix-*` header names (`NotificationsService`'s own doc
    // comment) -- mapped here, at the controller boundary.
    const headers: ResendWebhookHeaders = {
      id: svixId,
      timestamp: svixTimestamp,
      signature: svixSignature,
    };
    const verified = this.notificationsService.verifyWebhookSignature(
      request.rawBody.toString("utf-8"),
      headers,
    );
    if (verified === null) {
      // 401, matching `RevenueCatWebhookController`'s convention for a
      // failed signature/secret check (missing/malformed input above is
      // a 400; an input that parses but doesn't verify is a 401).
      throw new UnauthorizedException();
    }

    switch (body.type) {
      case "email.bounced":
      case "email.complained":
        for (const email of body.data.to ?? []) {
          await this.authService.markEmailUnverified(email);
        }
        break;
      case "email.delivery_delayed":
        // Logged only (ADR-023): no state change, Resend's own retry
        // schedule handles delivery.
        break;
      default:
        // Unknown/future event type: ack without acting on it.
        break;
    }

    return { received: true };
  }
}
