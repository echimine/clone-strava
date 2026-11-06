import { Controller, HttpCode, HttpStatus, Inject, Post, ServiceUnavailableException, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import jwt from "jsonwebtoken";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { z } from "zod";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { CONFIG, type ApiEnv } from "../config/env.js";

/** The Live server refuses a token past 5 minutes, and a `name` past 30 visible characters. */
export const LIVE_PARTICIPANT_TOKEN_TTL_SECONDS = 5 * 60;
const MAX_NAME_GRAPHEMES = 30;
const FALLBACK_NAME = "Athlète";

const liveParticipantTokenResponseSchema = z.object({ token: z.string() });
class LiveParticipantTokenResponseDto extends createZodDto(liveParticipantTokenResponseSchema) {}

const graphemes = new Intl.Segmenter("fr", { granularity: "grapheme" });

/** At most 30 visible characters, a composed emoji never cut; never empty. */
export function participantName(name: string): string {
  const visible = Array.from(graphemes.segment(name.trim()), (part) => part.segment);
  return visible.slice(0, MAX_NAME_GRAPHEMES).join("") || FALLBACK_NAME;
}

/**
 * `POST /v1/live/participant-token`: the Participant token the Live SDK (live.echimine.fr) asks
 * for at each connection, a 5 min HS256 JWT signed with Nervo's member app secret (`iss` the
 * member app, `sub` the user, `name` their name). The Live server alone decides who is Host,
 * Co-host or Viewer. `503 live_not_configured` without `LIVE_TOKEN_SECRET`.
 */
@Controller("live")
@UseGuards(SessionGuard)
export class LiveParticipantTokenController {
  constructor(@Inject(CONFIG) private readonly config: ApiEnv) {}

  @Post("participant-token")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: LiveParticipantTokenResponseDto })
  @ApiResponse({ status: 503, description: "`live_not_configured`: no `LIVE_TOKEN_SECRET`" })
  issue(@CurrentUser() user: AuthenticatedUser): { token: string } {
    const secret = this.config.LIVE_TOKEN_SECRET;
    if (!secret) {
      throw new ServiceUnavailableException({ code: "live_not_configured", message: "Live is not configured" });
    }
    const token = jwt.sign({ name: participantName(user.name) }, secret, {
      algorithm: "HS256",
      issuer: this.config.LIVE_APP_ID,
      subject: user.userId,
      expiresIn: LIVE_PARTICIPANT_TOKEN_TTL_SECONDS,
    });
    return { token };
  }
}
