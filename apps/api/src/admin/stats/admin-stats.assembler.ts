import { Injectable } from "@nestjs/common";
import type { AdminGrowthStats, AdminStatsPeriod, AdminTodoStats, AdminTrend } from "@repo/contracts";
import { ActivitiesService, type ActivityGrowthCounts } from "@repo/core/activities";
import { AuthService } from "@repo/core/auth";
import { EngagementService } from "@repo/core/engagement";
import { SocialService } from "@repo/core/social";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { FailedJobsSource } from "./sources/failed-jobs.source.js";
import { OpenReportsSource } from "./sources/open-reports.source.js";
import { PromotionalPremiumSource } from "./sources/promotional-premium.source.js";
import { SuspiciousEffortsSource } from "./sources/suspicious-efforts.source.js";
import { statsPeriodWindow, type StatsRange } from "./stats-period.js";

/** "Imports en échec sur 7 jours". */
const FAILED_IMPORTS_WINDOW_MS = 7 * 86_400_000;

/** The current instant; replaced in tests to put the Growth periods where only their data is. */
@Injectable()
export class StatsClock {
  now(): Date {
    return new Date();
  }
}

/**
 * The backoffice dashboard (ADR-038 §15), composed here because "admin is not a module"
 * (ADR-021 §1): each module counts its own rows, `auth` names the Administrators the counts leave
 * out. Everything is computed on the fly; nothing is written to the Journal.
 */
@Injectable()
export class AdminStatsAssembler {
  constructor(
    private readonly clock: StatsClock,
    private readonly auth: AuthService,
    private readonly activities: ActivitiesService,
    private readonly engagement: EngagementService,
    private readonly social: SocialService,
    private readonly subscriptions: SubscriptionsService,
    private readonly openReports: OpenReportsSource,
    private readonly suspiciousEfforts: SuspiciousEffortsSource,
    private readonly promotionalPremium: PromotionalPremiumSource,
    private readonly failedJobs: FailedJobsSource,
  ) {}

  /**
   * "À traiter": the work waiting now, Administrators left out like everywhere on the dashboard:
   * open reports on them or their content, their failed Activities and imports. A failed job is
   * not attributed to anyone, so every one counts.
   */
  async todo(): Promise<AdminTodoStats> {
    const now = this.clock.now();
    const adminIds = await this.auth.listAdminIds();
    const [openReports, failures, failedJobs, suspiciousEfforts] = await Promise.all([
      this.openReports.count(adminIds),
      this.activities.getAdminFailureCounts(new Date(now.getTime() - FAILED_IMPORTS_WINDOW_MS), adminIds),
      this.failedJobs.count(),
      this.suspiciousEfforts.count(),
    ]);
    return {
      openReports: {
        count: openReports.count,
        oldestOpenedAt: openReports.oldestOpenedAt?.toISOString() ?? null,
      },
      failedActivities: failures.failedActivities,
      failedImports: failures.failedImports,
      failedJobs,
      suspiciousEfforts,
    };
  }

  /** "Croissance": the period against the previous one of the same length, and the daily chart. */
  async growth(period: AdminStatsPeriod): Promise<AdminGrowthStats> {
    const now = this.clock.now();
    const window = statsPeriodWindow(period, now);
    const adminIds = await this.auth.listAdminIds();
    const [current, previous, premiumNow, promotionalActive, dailyActivities] = await Promise.all([
      this.countPeriod(window.current, adminIds),
      this.countPeriod(window.previous, adminIds),
      this.subscriptions.countActivePremium(now, adminIds),
      this.promotionalPremium.countActive(now, adminIds),
      this.activities.countActivitiesPerParisDay(window.current, adminIds),
    ]);
    const trend = (pick: (counts: PeriodCounts) => number): AdminTrend => ({
      value: pick(current),
      previous: pick(previous),
    });
    return {
      period,
      from: window.days[0]!,
      to: window.days.at(-1)!,
      signUps: trend((counts) => total(counts.signUpsPerDay)),
      activeAthletes: trend((counts) => counts.activities.activeAthletes),
      activities: {
        total: trend((counts) => activityTotal(counts.activities)),
        recorded: trend((counts) => counts.activities.recorded),
        imported: trend((counts) => counts.activities.imported),
        manual: trend((counts) => counts.activities.manual),
      },
      premium: {
        payingActive: premiumNow.payingActive,
        trialsActive: premiumNow.trialsActive,
        promotionalActive,
        trialsStarted: trend((counts) => counts.premiumStarts.trialsStarted),
        newPaying: trend((counts) => counts.premiumStarts.newPaying),
      },
      engagement: {
        kudos: trend((counts) => counts.engagement.kudos),
        comments: trend((counts) => counts.engagement.comments),
        follows: trend((counts) => counts.follows),
        media: trend((counts) => counts.activities.media),
      },
      daily: window.days.map((day) => ({
        day,
        signUps: current.signUpsPerDay.get(day) ?? 0,
        activities: dailyActivities.get(day) ?? 0,
      })),
    };
  }

  private async countPeriod(range: StatsRange, adminIds: string[]): Promise<PeriodCounts> {
    const [signUpsPerDay, activities, engagement, follows, premiumStarts] = await Promise.all([
      this.auth.countSignUpsPerParisDay(range),
      this.activities.getAdminGrowthCounts(range, adminIds),
      this.engagement.getAdminGrowthCounts(range, adminIds),
      this.social.countFollowsCreated(range, adminIds),
      this.subscriptions.countPremiumStarts(range, adminIds),
    ]);
    return { signUpsPerDay, activities, engagement, follows, premiumStarts };
  }
}

interface PeriodCounts {
  signUpsPerDay: Map<string, number>;
  activities: ActivityGrowthCounts;
  engagement: { kudos: number; comments: number };
  follows: number;
  premiumStarts: { trialsStarted: number; newPaying: number };
}

function total(perDay: Map<string, number>): number {
  return [...perDay.values()].reduce((sum, count) => sum + count, 0);
}

function activityTotal(counts: ActivityGrowthCounts): number {
  return counts.recorded + counts.imported + counts.manual;
}
