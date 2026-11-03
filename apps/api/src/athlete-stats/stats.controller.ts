import { Controller, Get, NotFoundException, Param, ParseUUIDPipe, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  athleteStatsQuerySchema,
  athleteStatsResponseSchema,
  progressQuerySchema,
  progressResponseSchema,
  type AthleteStatsResponse,
  type ProgressResponse,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AuthService } from "@repo/core/auth";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

class ProgressQueryDto extends createZodDto(progressQuerySchema) {}
class ProgressResponseDto extends createZodDto(progressResponseSchema) {}
class AthleteStatsQueryDto extends createZodDto(athleteStatsQuerySchema) {}
class AthleteStatsResponseDto extends createZodDto(athleteStatsResponseSchema) {}

/**
 * Progrès and Statistiques (ADR-036 §4). Weeks run Monday to Sunday in `Europe/Paris`; every
 * figure covers only the Activities the viewer may see (ADR-036 §3).
 */
@Controller()
@UseGuards(SessionGuard)
export class AthleteStatsController {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly auth: AuthService,
  ) {}

  /**
   * The viewer's own 12 weeks for one sport, oldest first and ending with the current week
   * (zero-filled), and that sport's Streak with the current month's active days. `422` for a
   * missing, unknown or inactive sport.
   */
  @Get("me/progress")
  @ZodResponse({ status: 200, type: ProgressResponseDto })
  progress(@Query() query: ProgressQueryDto, @CurrentUser() user: AuthenticatedUser): Promise<ProgressResponse> {
    return this.activities.getProgress(user.userId, query.sport);
  }

  /**
   * An athlete's statistics: averages of the 4 full weeks before the current one, year to date
   * and all time. `sport` omitted means all sports; `422` for an unknown or inactive sport, `404
   * athlete_not_found` for an unknown athlete.
   */
  @Get("athletes/:id/stats")
  @ZodResponse({ status: 200, type: AthleteStatsResponseDto })
  async stats(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @Query() query: AthleteStatsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<AthleteStatsResponse> {
    const [identity] = await this.auth.getPublicIdentities([athleteId]);
    if (!identity) {
      throw new NotFoundException({ code: "athlete_not_found", message: "Athlete not found" });
    }
    return this.activities.getAthleteStats(user.userId, athleteId, query.sport);
  }
}
