import { Controller, Get, Headers, Param, ParseUUIDPipe, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  leaderboardQuerySchema,
  leaderboardResponseSchema,
  segmentSheetSchema,
  type LeaderboardResponse,
  type SegmentSheet,
} from "@repo/contracts";
import { SegmentsService, type LeaderboardReader } from "@repo/core/segments";
import { SocialService } from "@repo/core/social";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { toLeaderboardResponse, toSegmentSheet } from "./segment-sheet-assembler.js";

class LeaderboardQueryDto extends createZodDto(leaderboardQuerySchema) {}
class LeaderboardResponseDto extends createZodDto(leaderboardResponseSchema) {}
class SegmentSheetDto extends createZodDto(segmentSheetSchema) {}

/** `GET /v1/segments/:id` and its Leaderboard (ADR-039 §8, §9, §12). */
@Controller("segments")
@UseGuards(SessionGuard)
export class SegmentSheetController {
  constructor(
    private readonly segments: SegmentsService,
    private readonly subscriptions: SubscriptionsService,
    private readonly social: SocialService,
    private readonly viewerFilter: ViewerFilter,
    private readonly identities: AthleteIdentities,
  ) {}

  /**
   * The sheet: figures, profile, favourites, the viewer's Efforts, the Local Legend (Tous), the
   * top 10 and the viewer's line. Free; `404 segment_not_found` once deleted.
   */
  @Get(":id")
  @ZodResponse({ status: 200, type: SegmentSheetDto })
  async sheet(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<SegmentSheet> {
    const reader = await this.reader(user.userId, false);
    const sheet = await this.segments.getSheet(segmentId, reader);
    return toSegmentSheet(sheet, await this.identities.resolve(this.athletesOf(sheet.leaderboard)));
  }

  /**
   * `{ limited, entries, me, localLegend }`. Without Premium: the top 10 of Tous and the viewer's
   * line; a filter, a sex other than Tous or a cursor answer `403 premium_required`. With
   * Premium: pages of 50. `tz` (or the `x-time-zone` header) is the viewer's time zone for
   * `filter=period`.
   */
  @Get(":id/leaderboard")
  @ZodResponse({ status: 200, type: LeaderboardResponseDto })
  async leaderboard(
    @Param("id", ParseUUIDPipe) segmentId: string,
    @Query() query: LeaderboardQueryDto,
    @Headers("x-time-zone") timeZoneHeader: string | undefined,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<LeaderboardResponse> {
    const reader = await this.reader(user.userId, query.filter === "following");
    const view = await this.segments.getLeaderboard(
      segmentId,
      {
        gender: query.gender,
        filter: query.filter,
        value: query.value,
        timeZone: query.tz ?? timeZoneHeader,
        cursor: query.cursor,
      },
      reader,
    );
    return toLeaderboardResponse(view, await this.identities.resolve(this.athletesOf(view)));
  }

  private async reader(viewerId: string, withFollowees: boolean): Promise<LeaderboardReader> {
    const [exclusions, isPremium, followingIds] = await Promise.all([
      this.viewerFilter.for(viewerId),
      this.subscriptions.isPremium(viewerId),
      withFollowees ? this.social.getFolloweeIds(viewerId) : Promise.resolve([]),
    ]);
    return { viewerId, exclusions, isPremium, followingIds };
  }

  private athletesOf(view: Parameters<typeof toLeaderboardResponse>[0]): string[] {
    return [
      ...view.entries.map((entry) => entry.userId),
      ...(view.me ? [view.me.userId] : []),
      ...(view.localLegend.legend ? [view.localLegend.legend.userId] : []),
    ];
  }
}
