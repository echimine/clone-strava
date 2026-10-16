import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  realtimeGrantRequestSchema,
  realtimeGrantResponseSchema,
  type RealtimeGrantResponse,
} from "@repo/contracts";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { RealtimeGrantIssuer } from "./realtime-grant-issuer.js";

class RealtimeGrantRequestDto extends createZodDto(realtimeGrantRequestSchema) {}
class RealtimeGrantResponseDto extends createZodDto(realtimeGrantResponseSchema) {}

/**
 * `POST /v1/realtime/grants` (ADR-034 §5, amends ADR-010 §3): a 60 s
 * subscription grant for one topic that is not in the connection token.
 * `404 activity_not_found` when the Activity is not visible.
 */
@Controller("realtime")
@UseGuards(SessionGuard)
export class RealtimeGrantsController {
  constructor(private readonly issuer: RealtimeGrantIssuer) {}

  @Post("grants")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: RealtimeGrantResponseDto })
  @ApiResponse({ status: 404, description: "`activity_not_found`: the Activity is not visible" })
  @ApiResponse({ status: 422, description: "`validation_error`: not an `activity:{uuid}` topic" })
  grant(@Body() body: RealtimeGrantRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<RealtimeGrantResponse> {
    return this.issuer.grant(user.userId, body.topic);
  }
}
