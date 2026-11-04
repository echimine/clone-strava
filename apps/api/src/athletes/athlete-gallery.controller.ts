import { Controller, Get, Param, ParseUUIDPipe, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { galleryQuerySchema, galleryResponseSchema, type GalleryResponse } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { assertAthleteVisible, ViewerFilter } from "../viewer-filter/viewer-filter.js";

class GalleryQueryDto extends createZodDto(galleryQuerySchema) {}
class GalleryResponseDto extends createZodDto(galleryResponseSchema) {}

/**
 * An athlete's Gallery (ADR-037 §9): the Media of their processed Activities the viewer may see,
 * with the rule of `GET /v1/athletes/:id/activities`, signed like every Media (§1, §7). An
 * unknown athlete is `404 athlete_not_found`.
 */
@Controller("athletes")
@UseGuards(SessionGuard)
export class AthleteGalleryController {
  constructor(
    private readonly identities: AthleteIdentities,
    private readonly activities: ActivitiesService,
    private readonly media: MediaAssembler,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /** Newest Activity first, then the Media order; keyset pages (`422 invalid_cursor` on a foreign cursor). */
  @Get(":id/media")
  @ZodResponse({ status: 200, type: GalleryResponseDto })
  async gallery(
    @Param("id", ParseUUIDPipe) athleteId: string,
    @Query() query: GalleryQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<GalleryResponse> {
    const filter = await this.viewerFilter.for(user.userId);
    assertAthleteVisible(filter, athleteId);
    await this.identities.assertExists(athleteId);
    const page = await this.activities.getAthleteGalleryPage(user.userId, athleteId, query, filter);
    const items = await Promise.all(
      page.items.map(async (record) => ({
        ...(await this.media.sign(record)),
        activity: {
          id: record.activity.id,
          title: record.activity.title,
          startedAt: record.activity.startedAt.toISOString(),
        },
      })),
    );
    return { items, nextCursor: page.nextCursor };
  }
}
