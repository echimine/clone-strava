import { Injectable } from "@nestjs/common";
import {
  ADMIN_ACTIVITY_DETAIL_LIST_LIMIT,
  type AdminActivityDetail,
  type AdminActivityListItem,
} from "@repo/contracts";
import { ActivitiesService, type AdminActivityRow } from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { SegmentsService } from "@repo/core/segments";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { MediaAssembler } from "../../media/media-assembler.js";

/**
 * Composes the backoffice Activities screen (ADR-038 §11) from the modules that own each part:
 * the Activity and its Media (`activities`), comments and kudos (`engagement`), efforts
 * (`segments`), names and Avatars (`users`, `auth`). One batch call per module.
 */
@Injectable()
export class AdminActivityAssembler {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly engagement: EngagementService,
    private readonly segments: SegmentsService,
    private readonly identities: AthleteIdentities,
    private readonly media: MediaAssembler,
  ) {}

  async listItems(rows: AdminActivityRow[]): Promise<AdminActivityListItem[]> {
    const athlete = await this.identities.resolve(rows.map((row) => row.userId));
    return rows.map((row) => ({
      id: row.id,
      title: row.title,
      athlete: athlete(row.userId),
      sportTypeCode: row.sportTypeCode,
      processingStatus: row.processingStatus,
      source: row.source,
      visibility: row.visibility,
      startedAt: row.startedAt.toISOString(),
      createdAt: row.createdAt.toISOString(),
      distanceM: row.distanceM,
    }));
  }

  async detail(activityId: string): Promise<AdminActivityDetail> {
    const activity = await this.activities.getForAdmin(activityId);
    const [comments, kudos, counts, efforts, signedMedia] = await Promise.all([
      this.engagement.listCommentsForAdmin(activity.id, ADMIN_ACTIVITY_DETAIL_LIST_LIMIT),
      this.engagement.listKudosForAdmin(activity.id, ADMIN_ACTIVITY_DETAIL_LIST_LIMIT),
      this.engagement.getCounts([activity.id]),
      this.segments.getActivityEfforts(activity.id),
      Promise.all(activity.media.map((media) => this.media.sign(media))),
    ]);
    const athlete = await this.identities.resolve([
      activity.userId,
      ...comments.map((comment) => comment.userId),
      ...kudos.map((given) => given.userId),
    ]);
    const engagement = counts.get(activity.id);
    return {
      id: activity.id,
      title: activity.title,
      description: activity.description,
      athlete: athlete(activity.userId),
      sportTypeCode: activity.sportTypeCode,
      visibility: activity.visibility,
      source: activity.source,
      processingStatus: activity.processingStatus,
      processingError: activity.processingError,
      processingAttempts: activity.processingAttempts,
      startedAt: activity.startedAt.toISOString(),
      endedAt: activity.endedAt.toISOString(),
      createdAt: activity.createdAt.toISOString(),
      updatedAt: activity.updatedAt.toISOString(),
      processedAt: activity.processedAt?.toISOString() ?? null,
      stats: activity.stats,
      route: activity.route,
      locationName: activity.locationName,
      media: signedMedia,
      comments: comments.map((comment) => ({
        id: comment.id,
        author: athlete(comment.userId),
        body: comment.body,
        createdAt: comment.createdAt.toISOString(),
        updatedAt: comment.updatedAt?.toISOString() ?? null,
      })),
      commentCount: engagement?.commentCount ?? 0,
      kudos: kudos.map((given) => ({ athlete: athlete(given.userId), createdAt: given.createdAt.toISOString() })),
      kudosCount: engagement?.kudosCount ?? 0,
      import: activity.import,
      efforts: efforts.map((effort) => ({ ...effort, startedAt: effort.startedAt.toISOString() })),
    };
  }
}
