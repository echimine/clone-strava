import { Injectable } from "@nestjs/common";
import type { FeedItem } from "@repo/contracts";
import type { FeedActivity } from "@repo/core/activities";
import { AuthService } from "@repo/core/auth";
import { EngagementService } from "@repo/core/engagement";
import { UsersService } from "@repo/core/users";

/**
 * Feed steps 3-4 of ADR-021 §6 (ADR-029): adds authors and engagement to a
 * page of activities with batch calls, one per module. Lives in `apps/api`
 * because `activities` (layer 2) may not call `engagement` (layer 3).
 * Reused by every activity list (feed, profile).
 */
@Injectable()
export class FeedAssembler {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
    private readonly engagement: EngagementService,
  ) {}

  async assemble(viewerId: string, activities: FeedActivity[]): Promise<FeedItem[]> {
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

    return activities.map((activity) => {
      const summary = summaryById.get(activity.userId);
      const identity = identityById.get(activity.userId);
      // `user_profile` names win; Better Auth's account name is the fallback.
      const profileName = [summary?.firstName, summary?.lastName].filter(Boolean).join(" ").trim();
      const count = counts.get(activity.id);
      return {
        id: activity.id,
        title: activity.title,
        sportTypeCode: activity.sportTypeCode,
        startedAt: activity.startedAt.toISOString(),
        visibility: activity.visibility,
        locationName: activity.locationName,
        stats: activity.stats,
        map: activity.mapPolyline ? { polyline: activity.mapPolyline, precision: 5 as const } : null,
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
    });
  }
}
