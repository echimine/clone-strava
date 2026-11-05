import {
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  ParseFloatPipe,
  ParseUUIDPipe,
  UseGuards,
} from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

/** `/v1/activities/:id/best-efforts` (ADR-039 §3, §12): the author's Best efforts. */
@Controller("activities/:id/best-efforts")
@UseGuards(SessionGuard)
export class BestEffortsController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  /**
   * The author removes a Best effort of their Activity for good (« Retirer ce temps de mes
   * meilleurs efforts »): `204`, again without effect. A recomputation never brings it back; the
   * Medals on that distance are replayed. `404 best_effort_not_found` for another athlete or a
   * distance (meters, e.g. `21097.5`) without a Best effort.
   */
  @Delete(":distanceM")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Removed" })
  async remove(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Param("distanceM", ParseFloatPipe) distanceM: number,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    await this.activitiesService.removeBestEffort(user.userId, activityId, distanceM);
  }
}
