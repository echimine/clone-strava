import { Controller, Get, Param, ParseUUIDPipe, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { activityResultsSchema, type ActivityResults } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { SegmentsService } from "@repo/core/segments";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";

class ActivityResultsDto extends createZodDto(activityResultsSchema) {}

/**
 * `/v1/activities/:id/results` (ADR-039 §12): « Résultats » of an Activity, composed here from
 * `activities` (Best efforts) and `segments` (Efforts), since neither may call the other's reads
 * for the viewer.
 */
@Controller("activities")
@UseGuards(SessionGuard)
export class ActivityResultsController {
  constructor(
    private readonly activitiesService: ActivitiesService,
    private readonly segmentsService: SegmentsService,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /**
   * Same rights as the detail (`404 activity_not_found` otherwise). Best efforts not removed,
   * shortest first, `removable` for the author only; Efforts in trace order, those in the
   * privacy zone left out for everyone but the author; `matchingInProgress` until the Activity
   * is matched with the current version.
   */
  @Get(":id/results")
  @ZodResponse({ status: 200, type: ActivityResultsDto })
  async results(
    @Param("id", ParseUUIDPipe) activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ActivityResults> {
    const filter = await this.viewerFilter.for(user.userId);
    const activity = await this.activitiesService.getDetail(user.userId, activityId, filter);
    const [{ poolLengthM, bestEfforts }, { matchingInProgress, efforts }] = await Promise.all([
      this.activitiesService.getBestEffortResults(activity.id),
      this.segmentsService.getActivityResults(activity.id, user.userId),
    ]);
    const removable = activity.userId === user.userId;
    return {
      matchingInProgress,
      poolLengthM,
      bestEfforts: bestEfforts.map((effort) => ({ ...effort, removable })),
      efforts,
    };
  }
}
