import { Injectable } from "@nestjs/common";
import type { ActivityDetail, FeedItem } from "@repo/contracts";
import type { ActivityDetailRecord, ActivityRecord, FeedActivity } from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { MediaAssembler } from "../media/media-assembler.js";

/** Kudos avatars on a card (ADR-036 §5). */
const RECENT_KUDOS_ON_CARD = 3;

/**
 * Feed steps 3-4 of ADR-021 §6 (ADR-029): adds authors, engagement and signed Media (ADR-037 §7)
 * to a page of activities with batch calls, one per module. Lives in `apps/api`
 * because `activities` (layer 2) may not call `engagement` (layer 3).
 * Reused by every activity list (feed, profile) and the activity detail (ADR-033 §2).
 */
@Injectable()
export class FeedAssembler {
  constructor(
    private readonly identities: AthleteIdentities,
    private readonly engagement: EngagementService,
    private readonly media: MediaAssembler,
  ) {}

  async assemble(viewerId: string, activities: FeedActivity[]): Promise<FeedItem[]> {
    const [{ social, recentKudos }, media] = await Promise.all([
      this.socialParts(viewerId, activities, RECENT_KUDOS_ON_CARD),
      this.media.forActivities(activities.map((activity) => activity.id)),
    ]);
    return activities.map((activity) => ({
      id: activity.id,
      title: activity.title,
      sportTypeCode: activity.sportTypeCode,
      startedAt: activity.startedAt.toISOString(),
      visibility: activity.visibility,
      locationName: activity.locationName,
      stats: activity.stats,
      map: toMap(activity.mapPolyline),
      routeTrimmed: activity.routeTrimmed,
      ...social(activity),
      recentKudos: recentKudos(activity),
      media: media(activity.id),
      mediaFirst: activity.mediaFirst,
    }));
  }

  /** The detail of one activity (ADR-033 §2): same author and engagement as its feed card. */
  async assembleDetail(viewerId: string, activity: ActivityDetailRecord): Promise<ActivityDetail> {
    const [{ social }, media] = await Promise.all([
      this.socialParts(viewerId, [activity], 0),
      this.media.forActivities([activity.id]),
    ]);
    return {
      id: activity.id,
      title: activity.title,
      description: activity.description ?? undefined,
      source: activity.source,
      importFormat: activity.importFormat ?? undefined,
      sportTypeCode: activity.sportTypeCode,
      startedAt: activity.startedAt.toISOString(),
      endedAt: activity.endedAt.toISOString(),
      visibility: activity.visibility,
      processingStatus: activity.processingStatus,
      processingError: activity.processingError ?? undefined,
      locationName: activity.locationName ?? undefined,
      stats: activity.stats,
      map: toMap(activity.mapPolyline),
      routeTrimmed: activity.routeTrimmed,
      analysis: activity.analysis,
      ...social(activity),
      media: media(activity.id),
      mediaFirst: activity.mediaFirst,
      updatedAt: activity.updatedAt.toISOString(),
    };
  }

  /**
   * Author, engagement and `viewerIsAuthor` of each activity, and its last `recentKudosCount`
   * kudos givers, with one batch call per module. Authors and givers share one identity lookup.
   */
  private async socialParts(viewerId: string, activities: ActivityRecord[], recentKudosCount: number) {
    const activityIds = activities.map((activity) => activity.id);
    const [[identity, recentGivers], counts, kudoed] = await Promise.all([
      this.engagement.getRecentKudoers(activityIds, recentKudosCount).then(async (givers) => {
        const userIds = [...activities.map((activity) => activity.userId), ...[...givers.values()].flat()];
        return [await this.identities.resolve(userIds), givers] as const;
      }),
      this.engagement.getCounts(activityIds),
      this.engagement.getKudoedBy(viewerId, activityIds),
    ]);

    return {
      social: (activity: ActivityRecord): Pick<FeedItem, "author" | "engagement" | "viewerIsAuthor"> => {
        const count = counts.get(activity.id);
        return {
          author: identity(activity.userId),
          engagement: {
            kudosCount: count?.kudosCount ?? 0,
            commentCount: count?.commentCount ?? 0,
            viewerHasKudoed: kudoed.has(activity.id),
          },
          viewerIsAuthor: activity.userId === viewerId,
        };
      },
      recentKudos: (activity: ActivityRecord): FeedItem["recentKudos"] =>
        (recentGivers.get(activity.id) ?? []).map((userId) => identity(userId)),
    };
  }
}

function toMap(polyline: string | null): FeedItem["map"] {
  return polyline ? { polyline, precision: 5 } : null;
}
