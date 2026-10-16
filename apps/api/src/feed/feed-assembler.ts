import { Injectable } from "@nestjs/common";
import type { ActivityDetail, FeedItem } from "@repo/contracts";
import type { ActivityDetailRecord, ActivityRecord, FeedActivity } from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { AthleteIdentities } from "../identities/athlete-identities.js";

/**
 * Feed steps 3-4 of ADR-021 §6 (ADR-029): adds authors and engagement to a
 * page of activities with batch calls, one per module. Lives in `apps/api`
 * because `activities` (layer 2) may not call `engagement` (layer 3).
 * Reused by every activity list (feed, profile) and the activity detail (ADR-033 §2).
 */
@Injectable()
export class FeedAssembler {
  constructor(
    private readonly identities: AthleteIdentities,
    private readonly engagement: EngagementService,
  ) {}

  async assemble(viewerId: string, activities: FeedActivity[]): Promise<FeedItem[]> {
    const social = await this.socialParts(viewerId, activities);
    return activities.map((activity) => ({
      id: activity.id,
      title: activity.title,
      sportTypeCode: activity.sportTypeCode,
      startedAt: activity.startedAt.toISOString(),
      visibility: activity.visibility,
      locationName: activity.locationName,
      stats: activity.stats,
      map: toMap(activity.mapPolyline),
      ...social(activity),
    }));
  }

  /** The detail of one activity (ADR-033 §2): same author and engagement as its feed card. */
  async assembleDetail(viewerId: string, activity: ActivityDetailRecord): Promise<ActivityDetail> {
    const social = await this.socialParts(viewerId, [activity]);
    return {
      id: activity.id,
      title: activity.title,
      description: activity.description ?? undefined,
      sportTypeCode: activity.sportTypeCode,
      startedAt: activity.startedAt.toISOString(),
      endedAt: activity.endedAt.toISOString(),
      visibility: activity.visibility,
      processingStatus: activity.processingStatus,
      processingError: activity.processingError ?? undefined,
      locationName: activity.locationName ?? undefined,
      stats: activity.stats,
      map: toMap(activity.mapPolyline),
      ...social(activity),
      updatedAt: activity.updatedAt.toISOString(),
    };
  }

  /** Author, engagement and `viewerIsAuthor` of each activity, with one batch call per module. */
  private async socialParts(viewerId: string, activities: ActivityRecord[]) {
    const activityIds = activities.map((activity) => activity.id);
    const [author, counts, kudoed] = await Promise.all([
      this.identities.resolve(activities.map((activity) => activity.userId)),
      this.engagement.getCounts(activityIds),
      this.engagement.getKudoedBy(viewerId, activityIds),
    ]);

    return (activity: ActivityRecord): Pick<FeedItem, "author" | "engagement" | "viewerIsAuthor"> => {
      const count = counts.get(activity.id);
      return {
        author: author(activity.userId),
        engagement: {
          kudosCount: count?.kudosCount ?? 0,
          commentCount: count?.commentCount ?? 0,
          viewerHasKudoed: kudoed.has(activity.id),
        },
        viewerIsAuthor: activity.userId === viewerId,
      };
    };
  }
}

function toMap(polyline: string | null): FeedItem["map"] {
  return polyline ? { polyline, precision: 5 } : null;
}
