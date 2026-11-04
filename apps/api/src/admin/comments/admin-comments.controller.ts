import { Body, Controller, Delete, HttpCode, HttpStatus, Param, ParseUUIDPipe, UseGuards } from "@nestjs/common";
import { ActivitiesService } from "@repo/core/activities";
import { EngagementService } from "@repo/core/engagement";
import { AdminGuard } from "../../auth/admin.guard.js";
import { CurrentUser } from "../../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../../auth/session.guard.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminReasonBodyDto } from "../sanctions/admin-reason-body.dto.js";
import { SanctionNotices } from "../sanctions/sanction-notices.js";

/** `/v1/admin/comments/*` (ADR-038 §11, §17). */
@Controller("admin/comments")
@UseGuards(SessionGuard, AdminGuard)
export class AdminCommentsController {
  constructor(
    private readonly engagement: EngagementService,
    private readonly activities: ActivitiesService,
    private readonly notices: SanctionNotices,
  ) {}

  /**
   * Sanction « Retirer un commentaire »: the soft delete of ADR-034 without the author check;
   * `404 comment_not_found` when unknown or already removed. The comment's author is the
   * athlete concerned.
   */
  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("comment.remove", { reason: "required" })
  async remove(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentUser() administrator: AuthenticatedUser,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    const comment = await this.engagement.removeCommentAsSanction(administrator.userId, id);
    audit.subjectUserId = comment.userId;
    const [activity] = await this.activities.getLabels([comment.activityId]);
    await this.notices.send({
      auditEntryId: audit.entryId,
      action: "comment.remove",
      athleteId: comment.userId,
      reason: body.reason,
      activity: activity ? { title: activity.title, startedAt: activity.startedAt.toISOString() } : null,
      comment: { body: comment.body, postedAt: comment.createdAt.toISOString() },
    });
  }
}
