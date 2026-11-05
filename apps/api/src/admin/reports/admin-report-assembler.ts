import { Injectable, NotFoundException } from "@nestjs/common";
import {
  ADMIN_REPORT_ERROR_CODES,
  type AdminReportAthlete,
  type AdminReportAuthor,
  type AdminReportCaseDetail,
  type AdminReportCaseListQuery,
  type AdminReportCaseListResponse,
  type AdminReportTargetContent,
  type ReportTargetType,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AuditService } from "@repo/core/audit";
import { AuthService } from "@repo/core/auth";
import { EngagementService } from "@repo/core/engagement";
import { ModerationService, type ReportCaseRecord } from "@repo/core/moderation";
import { UsersService } from "@repo/core/users";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { MediaAssembler } from "../../media/media-assembler.js";
import { auditTargetOf, changedSince, previewOf, readCopy, toAdminCopy, type TypedSnapshot } from "./report-copy.js";

/**
 * The case's target athlete. Only a Segment case may have none (ADR-039 §11), and the queue
 * leaves those out until #219.
 */
export function authorOf(reportCase: { targetUserId: string | null }): string {
  if (reportCase.targetUserId === null) {
    throw new Error("A Segment case has no target athlete; the queue does not read it yet (#219)");
  }
  return reportCase.targetUserId;
}

/** The target now, as shown and as a snapshot compared with the copies. */
interface CurrentTarget {
  content: AdminReportTargetContent;
  snapshot: TypedSnapshot;
}

/**
 * Composes the moderation queue (ADR-038 §10) from the modules that own each part: cases and
 * Reports (`moderation`), the target now (`activities`, `engagement`, `users`), names and Avatars
 * (`users`, `auth`), and the Sanctions read in the Journal (`audit`). `moderation` (layer 0) never
 * reads them itself.
 */
@Injectable()
export class AdminReportAssembler {
  constructor(
    private readonly moderation: ModerationService,
    private readonly audit: AuditService,
    private readonly auth: AuthService,
    private readonly activities: ActivitiesService,
    private readonly engagement: EngagementService,
    private readonly users: UsersService,
    private readonly identities: AthleteIdentities,
    private readonly media: MediaAssembler,
  ) {}

  async list(query: AdminReportCaseListQuery): Promise<AdminReportCaseListResponse> {
    const page = await this.moderation.listCases(
      {
        state: query.state,
        targetType: query.targetType,
        reason: query.reason,
        from: query.from,
        to: query.to,
        sort: query.sort,
        order: query.order,
      },
      { page: query.page, pageSize: query.pageSize },
    );
    const athlete = await this.athletes(page.items.map((row) => authorOf(row)));
    return {
      ...page,
      items: page.items.map((row) => ({
        id: row.id,
        targetType: row.targetType,
        targetId: row.targetId,
        status: row.status,
        openedAt: row.openedAt.toISOString(),
        closedAt: row.closedAt?.toISOString() ?? null,
        author: athlete(authorOf(row)),
        preview: previewOf(readCopy(row.targetType, row.firstSnapshot)),
        reportCount: row.reportCount,
        reasons: row.reasons,
      })),
    };
  }

  async detail(caseId: string): Promise<AdminReportCaseDetail> {
    const { reportCase, reports } = await this.getCase(caseId);
    const authorId = authorOf(reportCase);
    const people = [
      authorId,
      ...(reportCase.closedBy ? [reportCase.closedBy] : []),
      ...reports.flatMap((report) => (report.reporterId ? [report.reporterId] : [])),
    ];
    const [current, athlete, author, canResolve] = await Promise.all([
      this.readCurrent(reportCase.targetType, reportCase.targetId),
      this.athletes(people),
      this.author(authorId),
      this.canResolve(reportCase),
    ]);
    const person = (userId: string) => ({ id: userId, displayName: athlete(userId).displayName });
    return {
      id: reportCase.id,
      targetType: reportCase.targetType,
      targetId: reportCase.targetId,
      status: reportCase.status,
      openedAt: reportCase.openedAt.toISOString(),
      closedAt: reportCase.closedAt?.toISOString() ?? null,
      closedBy: reportCase.closedBy ? person(reportCase.closedBy) : null,
      closeNote: reportCase.closeNote,
      current: current?.content ?? null,
      author: { ...athlete(authorId), ...author },
      reports: reports.map((report) => {
        const copy = readCopy(reportCase.targetType, report.snapshot);
        return {
          id: report.id,
          reporter: report.reporterId ? person(report.reporterId) : null,
          reason: report.reason,
          note: report.note,
          createdAt: report.createdAt.toISOString(),
          copy: copy ? toAdminCopy(copy) : null,
          changedSince: changedSince(copy, current?.snapshot ?? null),
        };
      }),
      canResolve,
    };
  }

  /** The case, or `404 report_case_not_found` (also for a Segment case until #219, ADR-039 §11). */
  async getCase(caseId: string) {
    const found = await this.moderation.getCase(caseId);
    if (!found || found.reportCase.targetType === "segment") {
      throw new NotFoundException({ code: ADMIN_REPORT_ERROR_CODES.notFound, message: "Report case not found" });
    }
    return found;
  }

  /**
   * Whether « Sanctionné » is allowed (ADR-038 §10): the case is open and the Journal holds a
   * Sanction since its opening, on its target or on its author (a Ban of the author is enough).
   */
  async canResolve(reportCase: ReportCaseRecord): Promise<boolean> {
    if (reportCase.status !== "open") {
      return false;
    }
    const sanctions = await this.audit.countSanctions({
      subjectUserId: authorOf(reportCase),
      target: { type: auditTargetOf(reportCase.targetType), id: reportCase.targetId },
      since: reportCase.openedAt,
    });
    return sanctions > 0;
  }

  /** Names and Avatars; a deleted account has none (« Compte supprimé »). */
  private async athletes(userIds: string[]): Promise<(userId: string) => AdminReportAthlete> {
    const ids = [...new Set(userIds)];
    const [identity, existing] = await Promise.all([
      this.identities.resolve(ids),
      ids.length === 0 ? [] : this.auth.getPublicIdentities(ids),
    ]);
    const exists = new Set(existing.map((row) => row.userId));
    return (userId) => {
      if (!exists.has(userId)) {
        return { id: userId, displayName: null, avatarUrl: null };
      }
      const { displayName, avatarUrl } = identity(userId);
      return { id: userId, displayName, avatarUrl };
    };
  }

  /** The author's role, Ban, Reports received and past Sanctions (from the Journal). */
  private async author(userId: string): Promise<Omit<AdminReportAuthor, keyof AdminReportAthlete>> {
    const [account, reportsReceived, pastSanctions] = await Promise.all([
      this.auth.getAccountForAdmin(userId).catch((error: unknown) => {
        if (error instanceof NotFoundException) {
          return null;
        }
        throw error;
      }),
      this.moderation.countReportsReceived(userId),
      this.audit.countSanctions({ subjectUserId: userId }),
    ]);
    return { role: account?.role ?? null, banned: account?.ban != null, reportsReceived, pastSanctions };
  }

  private async readCurrent(targetType: ReportTargetType, targetId: string): Promise<CurrentTarget | null> {
    switch (targetType) {
      case "comment": {
        const comment = await this.engagement.findCommentForAdmin(targetId);
        if (!comment) {
          return null;
        }
        const [activity] = await this.activities.getLabels([comment.activityId]);
        return {
          content: {
            kind: "comment",
            body: comment.body,
            createdAt: comment.createdAt.toISOString(),
            updatedAt: comment.updatedAt?.toISOString() ?? null,
            activity: activity ? { id: activity.id, title: activity.title } : null,
          },
          snapshot: { kind: "comment", snapshot: { body: comment.body, activityId: comment.activityId } },
        };
      }
      case "activity": {
        const activity = await this.activities.getForAdmin(targetId).catch((error: unknown) => {
          if (error instanceof NotFoundException) {
            return null;
          }
          throw error;
        });
        if (!activity) {
          return null;
        }
        return {
          content: {
            kind: "activity",
            title: activity.title,
            description: activity.description,
            startedAt: activity.startedAt.toISOString(),
            media: await Promise.all(activity.media.map((media) => this.media.sign(media))),
          },
          snapshot: {
            kind: "activity",
            snapshot: {
              title: activity.title,
              description: activity.description,
              mediaIds: activity.media.map((media) => media.id),
            },
          },
        };
      }
      case "athlete": {
        const [known] = await this.auth.getPublicIdentities([targetId]);
        if (!known) {
          return null;
        }
        const [identity, profile, summary] = await Promise.all([
          this.identities.resolve([targetId]),
          this.users.getAdminProfile(targetId),
          this.users.getSummary(targetId),
        ]);
        const { displayName, avatarUrl } = identity(targetId);
        return {
          content: { kind: "athlete", displayName, bio: profile.bio, avatarUrl },
          snapshot: {
            kind: "athlete",
            snapshot: { name: displayName, bio: profile.bio, avatarKey: summary?.avatarKey ?? null },
          },
        };
      }
      case "segment":
        return null;
    }
  }
}
