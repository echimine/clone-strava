import { Body, Controller, HttpCode, HttpStatus, Inject, NotFoundException, Post, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import jwt from "jsonwebtoken";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { z } from "zod";
import { ActivitiesService } from "@repo/core/activities";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_GRANT_TTL_SECONDS,
  REALTIME_TOKEN_ALGORITHM,
  REALTIME_TOKEN_ISSUER,
  parseTopic,
  realtimeGrantClaimsSchema,
} from "@repo/realtime";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { CONFIG, type ApiEnv } from "../config/env.js";

/**
 * The only topic granted per request today (ADR-034 §5): `activity:{uuid}`,
 * lowercase, since the bridge publishes on the stored (lowercase) id and the
 * gateway matches topics exactly.
 */
const ACTIVITY_TOPIC_PATTERN = /^activity:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const realtimeGrantRequestSchema = z.object({
  topic: z.string().regex(ACTIVITY_TOPIC_PATTERN, "Expected activity:{uuid}"),
});
class RealtimeGrantRequestDto extends createZodDto(realtimeGrantRequestSchema) {}

const realtimeGrantResponseSchema = z.object({
  grant: z.string(),
  expiresInS: z.number().int(),
});
class RealtimeGrantResponseDto extends createZodDto(realtimeGrantResponseSchema) {}

/**
 * `POST /v1/realtime/grants` (ADR-034 §5, amends ADR-010 §3): a 60 s
 * subscription grant for one topic that is not in the connection token.
 * The gateway may not read the database (ADR-010 §1), so the API checks here
 * that the user may receive the topic, and the gateway only verifies the
 * signature. `404 activity_not_found` when the Activity is not visible.
 */
@Controller("realtime")
@UseGuards(SessionGuard)
export class RealtimeGrantsController {
  constructor(
    @Inject(CONFIG) private readonly config: ApiEnv,
    private readonly activities: ActivitiesService,
  ) {}

  @Post("grants")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: RealtimeGrantResponseDto })
  @ApiResponse({ status: 404, description: "`activity_not_found`: the Activity is not visible" })
  @ApiResponse({ status: 422, description: "`validation_error`: not an `activity:{uuid}` topic" })
  async grant(
    @Body() body: RealtimeGrantRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<{ grant: string; expiresInS: number }> {
    const topic = parseTopic(body.topic);
    const visible = topic.kind === "activity" && (await this.activities.getVisible(user.userId, topic.activityId));
    if (!visible) {
      throw new NotFoundException({ code: "activity_not_found", message: "Activity not found" });
    }

    const claims = realtimeGrantClaimsSchema.parse({ sub: user.userId, topic: body.topic });
    const grant = jwt.sign(claims, this.config.REALTIME_TOKEN_SECRET, {
      algorithm: REALTIME_TOKEN_ALGORITHM,
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
      expiresIn: REALTIME_GRANT_TTL_SECONDS,
    });
    return { grant, expiresInS: REALTIME_GRANT_TTL_SECONDS };
  }
}
