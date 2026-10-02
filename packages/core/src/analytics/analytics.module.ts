import { Module, type DynamicModule } from "@nestjs/common";
import { ANALYTICS_OPTIONS, type AnalyticsModuleOptions } from "./analytics.constants.js";
import { AnalyticsService } from "./analytics.service.js";

/**
 * `analytics` platform module (ADR-021 §1): owns no table, no business
 * rule, wraps `posthog-node`. Every domain module and app may import it
 * (ADR-021 §2 "any layer ... may use analytics, storage").
 */
@Module({})
export class AnalyticsModule {
  static forRoot(options: AnalyticsModuleOptions): DynamicModule {
    return {
      module: AnalyticsModule,
      // Global: every domain module may use it (ADR-021 §2), registered once by each app.
      global: true,
      providers: [{ provide: ANALYTICS_OPTIONS, useValue: options }, AnalyticsService],
      exports: [AnalyticsService],
    };
  }
}
