import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Put, Query, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  followRequestListResponseSchema,
  followSettingsSchema,
  listFollowsQuerySchema,
  type FollowRequestListResponse,
  type FollowSettings,
} from "@repo/contracts";
import { SocialService } from "@repo/core/social";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { FollowListAssembler } from "./follow-list-assembler.js";

class ListFollowsQueryDto extends createZodDto(listFollowsQuerySchema) {}
class FollowRequestListResponseDto extends createZodDto(followRequestListResponseSchema) {}
class FollowSettingsDto extends createZodDto(followSettingsSchema) {}

/**
 * The signed-in athlete's side of follows (ADR-036 §1): incoming requests,
 * removing a follower, and "Approuver mes abonnés".
 */
@Controller("me")
@UseGuards(SessionGuard)
export class MeFollowsController {
  constructor(
    private readonly social: SocialService,
    private readonly assembler: FollowListAssembler,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /** Incoming `pending` follows, most recent first, keyset pages. */
  @Get("follow-requests")
  @ZodResponse({ status: 200, type: FollowRequestListResponseDto })
  async requests(
    @Query() query: ListFollowsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<FollowRequestListResponse> {
    const filter = await this.viewerFilter.for(user.userId);
    return this.assembler.assembleRequests(await this.social.listFollowRequests(user.userId, query, filter));
  }

  /** Accept a request; `404 follow_request_not_found` without one. */
  @Put("follow-requests/:followerId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Accepted" })
  accept(
    @Param("followerId", ParseUUIDPipe) followerId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    return this.social.acceptRequest(user.userId, followerId);
  }

  /** Refuse a request. Idempotent. */
  @Delete("follow-requests/:followerId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Refused" })
  refuse(
    @Param("followerId", ParseUUIDPipe) followerId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    return this.social.refuseRequest(user.userId, followerId);
  }

  /** Remove an accepted follower. Idempotent. */
  @Delete("followers/:followerId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Removed" })
  removeFollower(
    @Param("followerId", ParseUUIDPipe) followerId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    return this.social.removeFollower(user.userId, followerId);
  }

  /** Turning approval off accepts every pending request in the same transaction. */
  @Put("follow-settings")
  @ZodResponse({ status: 200, type: FollowSettingsDto })
  updateSettings(@Body() body: FollowSettingsDto, @CurrentUser() user: AuthenticatedUser): Promise<FollowSettings> {
    return this.social.updateFollowSettings(user.userId, body.approveFollowers);
  }
}
