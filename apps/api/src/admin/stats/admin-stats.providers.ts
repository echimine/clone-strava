import { BullModule } from "@nestjs/bullmq";
import type { DynamicModule, Provider, Type } from "@nestjs/common";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { ModerationModule } from "@repo/core/moderation";
import { SocialModule } from "@repo/core/social";
import { SubscriptionsModule } from "@repo/core/subscriptions";
import { AdminStatsAssembler, StatsClock } from "./admin-stats.assembler.js";
import { dashboardQueueNames, FailedJobsSource } from "./sources/failed-jobs.source.js";
import { OpenReportsSource } from "./sources/open-reports.source.js";
import { PromotionalPremiumSource } from "./sources/promotional-premium.source.js";
import { SuspiciousEffortsSource } from "./sources/suspicious-efforts.source.js";

export { StatsClock } from "./admin-stats.assembler.js";

/**
 * What `AdminStatsController` needs (ADR-038 §15), listed once for `AdminModule` and its spec:
 * the modules that count, and every counted queue (read-only producers, `getFailedCount`).
 */
export const ADMIN_STATS_IMPORTS: (Type | DynamicModule)[] = [
  ActivitiesModule,
  EngagementModule,
  ModerationModule,
  SocialModule,
  SubscriptionsModule,
  BullModule.registerQueue(...dashboardQueueNames().map((name) => ({ name }))),
];

export const ADMIN_STATS_PROVIDERS: Provider[] = [
  StatsClock,
  AdminStatsAssembler,
  OpenReportsSource,
  SuspiciousEffortsSource,
  PromotionalPremiumSource,
  FailedJobsSource,
];
