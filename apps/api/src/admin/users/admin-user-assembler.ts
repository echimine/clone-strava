import { Injectable } from "@nestjs/common";
import {
  ADMIN_USER_REPORTS_LIMIT,
  signInMethodsFromProviders,
  type AdminUserBan,
  type AdminUserDetail,
  type AdminUserListQuery,
  type AdminUserListResponse,
  type AdminUserReport,
  type AdminUserReportsResponse,
  type AdminUserSessionsResponse,
  type AdminUserState,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { activeBan, AuthService, type ActiveBan } from "@repo/core/auth";
import { ModerationService, type UserReportRow } from "@repo/core/moderation";
import { SocialService } from "@repo/core/social";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { UsersService } from "@repo/core/users";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { deviceLabel } from "./device-label.js";

/**
 * Composes the backoffice users area (ADR-038 §5, ADR-021 §1 "admin is not a module"): the
 * account (`auth`), the profile and the list query (`users`), Activities, Follows and Blocks,
 * Premium and Reports, one call per module.
 */
@Injectable()
export class AdminUserAssembler {
  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
    private readonly activities: ActivitiesService,
    private readonly social: SocialService,
    private readonly subscriptions: SubscriptionsService,
    private readonly moderation: ModerationService,
    private readonly identities: AthleteIdentities,
  ) {}

  async list(query: AdminUserListQuery): Promise<AdminUserListResponse> {
    const { page, pageSize, ...filter } = query;
    const now = new Date();
    const { rows, total } = await this.users.listForAdmin(filter, { page, pageSize }, now);
    const identity = await this.identities.resolve(rows.map((row) => row.id));
    return {
      items: rows.map((row) => {
        const ban = activeBan(row, now);
        return {
          athlete: identity(row.id),
          email: row.email,
          role: row.role,
          createdAt: row.createdAt.toISOString(),
          signInMethods: signInMethodsFromProviders(row.providerIds),
          activityCount: row.activityCount,
          lastActivityAt: row.lastActivityAt?.toISOString() ?? null,
          isPremium: row.isPremium,
          premiumState: row.premiumState,
          premiumEndsAt: row.premiumEndsAt?.toISOString() ?? null,
          state: stateOf(ban),
          ban: toBan(ban),
        };
      }),
      total,
      page,
      pageSize,
    };
  }

  /** `404 user_not_found` for an unknown account. */
  async detail(userId: string): Promise<AdminUserDetail> {
    const account = await this.auth.getAccountForAdmin(userId);
    const [identity, profile, summary, figures, followCounts, blockedByCount, premium] = await Promise.all([
      this.identities.resolve([userId]),
      this.users.getAdminProfile(userId),
      this.activities.getAdminSummary(userId),
      // The athlete as their own viewer: every Activity counts towards the Streak.
      this.activities.getAthleteProfileFigures(userId, userId),
      this.social.getFollowCounts([userId]),
      this.social.countBlockers(userId),
      this.subscriptions.getPremiumBilling(userId),
    ]);
    const follows = followCounts.get(userId) ?? { followerCount: 0, followingCount: 0 };
    return {
      athlete: identity(userId),
      email: account.email,
      role: account.role,
      createdAt: account.createdAt.toISOString(),
      state: stateOf(account.ban),
      ban: toBan(account.ban),
      premium,
      account: { signInMethods: account.signInMethods, twoFactorEnabled: account.twoFactorEnabled },
      profile,
      activity: {
        activityCount: summary.activityCount,
        lastActivityAt: summary.lastActivityAt?.toISOString() ?? null,
        streakWeeks: figures.streakWeeks,
      },
      follows: { ...follows, blockedByCount },
    };
  }

  async sessions(headers: Headers, userId: string): Promise<AdminUserSessionsResponse> {
    const sessions = await this.auth.listUserSessions(headers, userId);
    return {
      items: sessions.map((session) => ({
        id: session.id,
        device: deviceLabel(session.userAgent),
        userAgent: session.userAgent,
        createdAt: session.createdAt.toISOString(),
        expiresAt: session.expiresAt.toISOString(),
      })),
    };
  }

  /** `404 user_not_found` for an unknown account. */
  async reports(userId: string): Promise<AdminUserReportsResponse> {
    await this.auth.getAccountForAdmin(userId);
    const { received, sent } = await this.moderation.getReportsOfUser(userId, ADMIN_USER_REPORTS_LIMIT);
    return { received: received.map(toReport), sent: sent.map(toReport) };
  }
}

function stateOf(ban: ActiveBan | null): AdminUserState {
  if (!ban) {
    return "active";
  }
  return ban.until ? "temporarily_banned" : "banned";
}

function toBan(ban: ActiveBan | null): AdminUserBan | null {
  return ban ? { until: ban.until?.toISOString() ?? null, reason: ban.reason } : null;
}

function toReport(row: UserReportRow): AdminUserReport {
  return { ...row, createdAt: row.createdAt.toISOString() };
}
