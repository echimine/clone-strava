import { Controller, Delete, Get, Param, ParseUUIDPipe, Put, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  followListResponseSchema,
  followResponseSchema,
  listFollowsQuerySchema,
  type FollowListResponse,
  type FollowResponse,
} from "@repo/contracts";
import { SocialService, type FollowListKind } from "@repo/core/social";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { assertAthleteVisible, ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { FollowListAssembler } from "./follow-list-assembler.js";

class FollowResponseDto extends createZodDto(followResponseSchema) {}
class ListFollowsQueryDto extends createZodDto(listFollowsQuerySchema) {}
class FollowListResponseDto extends createZodDto(followListResponseSchema) {}

/**
 * `/v1/athletes/:id/follow`, `/followers`, `/following` (ADR-036 §1). An
 * unknown athlete is `404 athlete_not_found`.
 */
@Controller("athletes/:id")
@UseGuards(SessionGuard)
export class AthleteFollowsController {
  constructor(
    private readonly social: SocialService,
    private readonly identities: AthleteIdentities,
    private readonly assembler: FollowListAssembler,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /**
   * Follow: `accepted`, or `pending` when the athlete approves followers. Idempotent; self is `422
   * cannot_follow_self`; an athlete hidden from the viewer (ADR-038 §7) is `404 athlete_not_found`.
   */
  @Put("follow")
  @ZodResponse({ status: 200, type: FollowResponseDto })
  async follow(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FollowResponse> {
    assertAthleteVisible(await this.viewerFilter.for(user.userId), athleteId);
    await this.identities.assertExists(athleteId);
    return this.social.follow(user.userId, athleteId);
  }

  /** Unfollow, or cancel a pending request. Idempotent. */
  @Delete("follow")
  @ZodResponse({ status: 200, type: FollowResponseDto })
  async unfollow(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FollowResponse> {
    await this.identities.assertExists(athleteId);
    return this.social.unfollow(user.userId, athleteId);
  }

  /** Accepted followers, most recent first, keyset pages (`422 invalid_cursor` on a foreign cursor). */
  @Get("followers")
  @ZodResponse({ status: 200, type: FollowListResponseDto })
  followers(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @Query() query: ListFollowsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FollowListResponse> {
    return this.list(user.userId, athleteId, "followers", query);
  }

  /** Athletes this one follows (accepted), most recent first, keyset pages. */
  @Get("following")
  @ZodResponse({ status: 200, type: FollowListResponseDto })
  following(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @Query() query: ListFollowsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FollowListResponse> {
    return this.list(user.userId, athleteId, "following", query);
  }

  private async list(
    viewerId: string,
    athleteId: string,
    kind: FollowListKind,
    query: ListFollowsQueryDto,
  ): Promise<FollowListResponse> {
    const filter = await this.viewerFilter.for(viewerId);
    assertAthleteVisible(filter, athleteId);
    await this.identities.assertExists(athleteId);
    return this.assembler.assemble(await this.social.listFollows(viewerId, athleteId, kind, query, filter));
  }
}
