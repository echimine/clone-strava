import { Controller, Get, Param, ParseUUIDPipe, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  athleteProfileResponseSchema,
  feedQuerySchema,
  feedResponseSchema,
  type AthleteProfileResponse,
  type FeedResponse,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { AthleteProfileAssembler } from "./athlete-profile-assembler.js";

class AthleteProfileResponseDto extends createZodDto(athleteProfileResponseSchema) {}
class AthleteActivitiesQueryDto extends createZodDto(feedQuerySchema) {}
class AthleteActivitiesResponseDto extends createZodDto(feedResponseSchema) {}

/**
 * An athlete's profile and Activities (ADR-036 §3); the app passes its own id for its own profile.
 * Every figure covers only the Activities the viewer may see. An unknown athlete is `404
 * athlete_not_found`. `:id` must be a UUID, so `GET /v1/athletes/search` is never an athlete.
 */
@Controller("athletes")
@UseGuards(SessionGuard)
export class AthletesController {
  constructor(
    private readonly identities: AthleteIdentities,
    private readonly profiles: AthleteProfileAssembler,
    private readonly activities: ActivitiesService,
    private readonly feed: FeedAssembler,
  ) {}

  /** The profile header; `approveFollowers`, `pendingFollowRequestCount` and `itineraryCount` only for oneself. */
  @Get(":id")
  @ZodResponse({ status: 200, type: AthleteProfileResponseDto })
  async profile(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<AthleteProfileResponse> {
    await this.identities.assertExists(athleteId);
    return this.profiles.assemble(user.userId, athleteId);
  }

  /**
   * The athlete's processed Activities the viewer may see, newest first: the same items and
   * keyset pages as `GET /v1/feed` (`422 invalid_cursor` on a foreign cursor).
   */
  @Get(":id/activities")
  @ZodResponse({ status: 200, type: AthleteActivitiesResponseDto })
  async activitiesOf(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @Query() query: AthleteActivitiesQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FeedResponse> {
    await this.identities.assertExists(athleteId);
    const page = await this.activities.getAthleteActivitiesPage(user.userId, athleteId, query);
    return { items: await this.feed.assemble(user.userId, page.items), nextCursor: page.nextCursor };
  }
}
