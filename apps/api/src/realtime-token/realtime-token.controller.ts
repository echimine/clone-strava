import { Controller, Inject, Post, UseGuards } from "@nestjs/common";
import jwt from "jsonwebtoken";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import { z } from "zod";
import {
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  REALTIME_TOKEN_TTL_SECONDS,
  realtimeTokenClaimsSchema,
  userTopic,
} from "@repo/realtime";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard } from "../auth/session.guard.js";
import type { AuthenticatedUser } from "../auth/session.guard.js";
import { CONFIG, type ApiEnv } from "../config/env.js";

const realtimeTokenResponseSchema = z.object({ token: z.string() });
class RealtimeTokenResponseDto extends createZodDto(realtimeTokenResponseSchema) {}

/**
 * `POST /v1/realtime/token` (ADR-009 §4, ADR-010 §3): protected by the
 * session, returns a 60s JWT the mobile app uses to open the WebSocket
 * connection. The gateway verifies it locally, without calling the API.
 *
 * Only constants/types are imported from `@repo/realtime` here, never the
 * publisher (ADR-009 §4 note, ADR-021 §4: publishing stays behind the
 * `realtime` platform module of `packages/core`); `.dependency-cruiser.cjs`
 * only restricts `@repo/realtime` imports from *within* `packages/core`
 * (rule `only-realtime-module-imports-repo-realtime`), not from apps.
 */
@Controller("realtime")
@UseGuards(SessionGuard)
export class RealtimeTokenController {
  constructor(@Inject(CONFIG) private readonly config: ApiEnv) {}

  @Post("token")
  @ZodSerializerDto(RealtimeTokenResponseDto)
  issueToken(@CurrentUser() user: AuthenticatedUser): { token: string } {
    // MVP topics (ADR-010 §4): the user themselves, on all their devices.
    // Validated against the shared claims schema so a drift between this
    // payload and what `apps/realtime` expects fails loudly, here, rather
    // than as a silent `401` on every connection attempt.
    const claims = realtimeTokenClaimsSchema.parse({
      sub: user.userId,
      topics: [userTopic(user.userId)],
    });

    const token = jwt.sign(claims, this.config.REALTIME_TOKEN_SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_TOKEN_AUDIENCE,
      expiresIn: REALTIME_TOKEN_TTL_SECONDS,
    });
    return { token };
  }
}
