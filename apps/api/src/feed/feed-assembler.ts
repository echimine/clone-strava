import { Injectable } from "@nestjs/common";
import type { ActivityDetail, FeedItem } from "@repo/contracts";
import type { ActivityDetailRecord, ActivityRecord, FeedActivity } from "@repo/core/activities";
import { AuthService } from "@repo/core/auth";
import { EngagementService } from "@repo/core/engagement";
import { UsersService } from "@repo/core/users";

/**
 * Feed steps 3-4 of ADR-021 §6 (ADR-029): adds authors and engagement to a
 * page of activities with batch calls, one per module. Lives in `apps/api`
 * because `activities` (layer 2) may not call `engagement` (layer 3).
 * Reused by every activity list (feed, profile) and the activity detail (ADR-033 §2).
 */
@Injectable()
export class FeedAssembler {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
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
    const authorIds = [...new Set(activities.map((activity) => activity.userId))];
    const activityIds = activities.map((activity) => activity.id);
    const [summaries, identities, counts, kudoed] = await Promise.all([
      this.users.getSummaries(authorIds),
      this.auth.getPublicIdentities(authorIds),
      this.engagement.getCounts(activityIds),
      this.engagement.getKudoedBy(viewerId, activityIds),
    ]);
    const summaryById = new Map(summaries.map((summary) => [summary.userId, summary]));
    const identityById = new Map(identities.map((identity) => [identity.userId, identity]));

    return (activity: ActivityRecord): Pick<FeedItem, "author" | "engagement" | "viewerIsAuthor"> => {
      const summary = summaryById.get(activity.userId);
      const identity = identityById.get(activity.userId);
      // `user_profile` names win; Better Auth's account name is the fallback.
      const profileName = [summary?.firstName, summary?.lastName].filter(Boolean).join(" ").trim();
      const count = counts.get(activity.id);
      return {
        author: {
          id: activity.userId,
          displayName: profileName || identity?.name || "",
          avatarUrl: summary?.avatarUrl ?? identity?.image ?? null,
        },
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
