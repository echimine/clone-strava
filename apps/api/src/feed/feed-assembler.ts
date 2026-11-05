import { Injectable } from "@nestjs/common";
import type { ActivityDetail, FeedItem, MedalCounts } from "@repo/contracts";
import {
  ActivitiesService,
  type ActivityDetailRecord,
  type ActivityRecord,
  type FeedActivity,
  type MedalCount,
} from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { NO_EXCLUSIONS, type ViewerExclusions } from "@repo/core/infrastructure";
import { SegmentsService } from "@repo/core/segments";
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
    private readonly activities: ActivitiesService,
    private readonly segments: SegmentsService,
  ) {}

  async assemble(viewerId: string, activities: FeedActivity[], exclusions: ViewerExclusions): Promise<FeedItem[]> {
    const activityIds = activities.map((activity) => activity.id);
    const [{ social, recentKudos }, media, medalCounts] = await Promise.all([
      this.socialParts(viewerId, activities, RECENT_KUDOS_ON_CARD, exclusions),
      this.media.forActivities(activityIds),
      this.medalCounts(viewerId, activityIds),
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
      medalCounts: medalCounts(activity.id),
    }));
  }

  /** The detail of one activity (ADR-033 §2): same author and engagement as its feed card. */
  async assembleDetail(viewerId: string, activity: ActivityDetailRecord): Promise<ActivityDetail> {
    // No kudos avatars on the detail, so the viewer filter has nothing to hide here.
    const [{ social }, media, medalCounts] = await Promise.all([
      this.socialParts(viewerId, [activity], 0, NO_EXCLUSIONS),
      this.media.forActivities([activity.id]),
      this.medalCounts(viewerId, [activity.id]),
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
      medalCounts: medalCounts(activity.id),
      updatedAt: activity.updatedAt.toISOString(),
    };
  }

  /**
   * « Performances » of each activity (ADR-039 §12): the Medals of its Best efforts not removed
   * plus those of its Efforts the viewer may see, one batch call per module, never stored.
   */
  private async medalCounts(viewerId: string, activityIds: string[]) {
    const [bestEfforts, efforts] = await Promise.all([
      this.activities.countBestEffortMedals(activityIds),
      this.segments.countEffortMedals(activityIds, viewerId),
    ]);
    const totals = new Map<string, MedalCounts>();
    for (const { activityId, medal, count } of [...bestEfforts, ...efforts] as MedalCount[]) {
      const counts = totals.get(activityId) ?? { gold: 0, silver: 0, bronze: 0 };
      counts[medal] += count;
      totals.set(activityId, counts);
    }
    return (activityId: string): MedalCounts => totals.get(activityId) ?? { gold: 0, silver: 0, bronze: 0 };
  }

  /**
   * Author, engagement and `viewerIsAuthor` of each activity, and its last `recentKudosCount`
   * kudos givers (athletes hidden from the viewer left out, ADR-038 §7), with one batch call per
   * module. Authors and givers share one identity lookup.
   */
  private async socialParts(
    viewerId: string,
    activities: ActivityRecord[],
    recentKudosCount: number,
    exclusions: ViewerExclusions,
  ) {
    const activityIds = activities.map((activity) => activity.id);
    const [[identity, recentGivers], counts, kudoed] = await Promise.all([
      this.engagement.getRecentKudoers(activityIds, recentKudosCount, exclusions).then(async (givers) => {
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
