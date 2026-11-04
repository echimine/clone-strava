import { ConflictException, Injectable } from "@nestjs/common";
import { ActivitiesService, activityNotFound, type ActivityRecord } from "../../activities/index.js";
import { NO_EXCLUSIONS, type ViewerExclusions } from "../../infrastructure/index.js";

/**
 * First check of every comment route (ADR-034 §3): the viewer must see the
 * Activity (`404 activity_not_found`, through `ActivitiesService`, never a
 * direct table read: ADR-021 §2; the viewer filter applies, ADR-038 §7), and
 * it must be `processed` (`409 activity_not_commentable`, which only its
 * author can hit).
 */
@Injectable()
export class CommentableActivity {
  constructor(private readonly activities: ActivitiesService) {}

  /** Without `exclusions` (editing or deleting one's own comment), the viewer filter is not applied. */
  async get(viewerId: string, activityId: string, exclusions: ViewerExclusions = NO_EXCLUSIONS): Promise<ActivityRecord> {
    const activity = await this.activities.getVisible(viewerId, activityId, exclusions);
    if (!activity) {
      throw activityNotFound();
    }
    if (activity.processingStatus !== "processed") {
      throw new ConflictException({
        code: "activity_not_commentable",
        message: "Comments are only available on a processed activity",
      });
    }
    return activity;
  }
}
