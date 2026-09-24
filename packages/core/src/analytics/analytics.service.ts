import { Inject, Injectable, Optional, type OnApplicationShutdown } from "@nestjs/common";
import { PostHog } from "posthog-node";
import type {
  ActivityFailedProperties,
  ActivityProcessedProperties,
  AnalyticsEventName,
} from "@repo/contracts";
import { ANALYTICS_OPTIONS, type AnalyticsModuleOptions } from "./analytics.constants.js";

/**
 * Properties for each catalog event (ADR-015 "Event naming and catalog"),
 * mirroring `@repo/contracts`' `ANALYTICS_EVENTS` literal values. Kept
 * local rather than derived with `z.infer` so this module never needs a
 * direct `zod` dependency (`@repo/contracts` already validates payloads).
 */
export interface AnalyticsEventPropertiesMap {
  activity_processed: ActivityProcessedProperties;
  activity_failed: ActivityFailedProperties;
}

/**
 * `analytics` platform module (ADR-021 §1, ADR-015): thin `posthog-node`
 * wrapper, typed on the event catalog. No-op when no API key is
 * configured (ADR-021 "postHogEnvShape ... optional so a dev environment
 * can run without it").
 */
@Injectable()
export class AnalyticsService implements OnApplicationShutdown {
  private readonly client: PostHog | undefined;

  constructor(@Optional() @Inject(ANALYTICS_OPTIONS) options?: AnalyticsModuleOptions) {
    this.client = options?.apiKey
      ? new PostHog(options.apiKey, { host: options.host })
      : undefined;
  }

  /** Reliable server-side event (ADR-015 "Backend"): same `distinctId` as the database and RevenueCat. */
  capture<T extends AnalyticsEventName>(
    event: T,
    distinctId: string,
    properties: AnalyticsEventPropertiesMap[T],
  ): void {
    this.client?.capture({ distinctId, event, properties });
  }

  async onApplicationShutdown(): Promise<void> {
    await this.client?.shutdown();
  }
}
