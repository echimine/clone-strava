import { Injectable, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import type { ReportSnapshot, ReportTargetType } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { isAthleteHidden, type ViewerExclusions } from "@repo/core/infrastructure";
import { SegmentsService } from "@repo/core/segments";
import { UsersService } from "@repo/core/users";
import { AthleteIdentities } from "../identities/athlete-identities.js";

/**
 * What a Report needs from its target: its author and a copy of its texts (ADR-038 §9). No
 * author only for a Segment without a creator (ADR-039 §11).
 */
export interface ReportTarget {
  authorId: string | null;
  snapshot: ReportSnapshot;
}

/**
 * Reads a Report's target through the module that owns it (ADR-038 §9): it must exist and be
 * visible to the reporter (`404` otherwise, with the code of a read of that target), and not be
 * the reporter's own (`422 cannot_report_own_content`). Things the reporter already reported
 * stay readable here, so a repeat answers "Déjà signalé" rather than `404`.
 */
@Injectable()
export class ReportTargetReader {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly engagement: EngagementService,
    private readonly users: UsersService,
    private readonly identities: AthleteIdentities,
    private readonly segments: SegmentsService,
  ) {}

  async read(
    reporterId: string,
    targetType: ReportTargetType,
    targetId: string,
    filter: ViewerExclusions,
  ): Promise<ReportTarget> {
    const exclusions: ViewerExclusions = { ...filter, reportedActivityIds: [], reportedCommentIds: [] };
    const target = await this.readTarget(reporterId, targetType, targetId, exclusions);
    if (target.authorId === reporterId) {
      throw new UnprocessableEntityException({
        code: "cannot_report_own_content",
        message: "You cannot report your own content",
      });
    }
    return target;
  }

  private async readTarget(
    reporterId: string,
    targetType: ReportTargetType,
    targetId: string,
    exclusions: ViewerExclusions,
  ): Promise<ReportTarget> {
    switch (targetType) {
      case "comment": {
        const comment = await this.engagement.findVisibleComment(reporterId, targetId, exclusions);
        if (!comment) {
          throw new NotFoundException({ code: "comment_not_found", message: "Comment not found" });
        }
        return { authorId: comment.authorId, snapshot: { body: comment.body, activityId: comment.activityId } };
      }
      case "activity": {
        // `404 activity_not_found` when missing or not visible.
        const activity = await this.activities.getDetail(reporterId, targetId, exclusions);
        const media = await this.activities.getMedia([activity.id]);
        return {
          authorId: activity.userId,
          snapshot: {
            title: activity.title,
            description: activity.description,
            mediaIds: (media.get(activity.id) ?? []).map((item) => item.id),
          },
        };
      }
      case "athlete": {
        if (isAthleteHidden(exclusions, targetId)) {
          throw new NotFoundException({ code: "athlete_not_found", message: "Athlete not found" });
        }
        await this.identities.assertExists(targetId);
        const [identity, profile, summary] = await Promise.all([
          this.identities.resolve([targetId]),
          this.users.getEditableProfile(targetId),
          this.users.getSummary(targetId),
        ]);
        return {
          authorId: targetId,
          snapshot: {
            name: identity(targetId).displayName,
            bio: profile.bio,
            avatarKey: summary?.avatarKey ?? null,
          },
        };
      }
      case "segment": {
        // Always public; reporting it does not hide it (ADR-039 §11), so no viewer filter here.
        const segment = await this.segments.getReportTarget(targetId);
        if (!segment) {
          throw new NotFoundException({ code: "segment_not_found", message: "Segment not found" });
        }
        return { authorId: segment.createdBy, snapshot: { name: segment.name } };
      }
    }
  }
}
