import { Module } from "@nestjs/common";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { AnalyticsModule } from "@repo/core/analytics";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule } from "@repo/core/infrastructure";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import { StorageModule } from "@repo/core/storage";
import { AppBullModule } from "./bull/bull.module.js";
import { ConfigModule } from "./config/config.module.js";
import { loadConfig } from "./config/env.js";
import { HeartbeatModule } from "./heartbeat/heartbeat.module.js";
import { AppLoggingModule } from "./logging/logging.module.js";
import { ActivitiesProcessorModule } from "./processors/activities/activities.module.js";
import { SegmentsProcessorModule } from "./processors/segments/segments.module.js";
import { SubscriptionsProcessorModule } from "./processors/subscriptions/subscriptions.module.js";

// `forRoot(...)` dynamic modules below are synchronous (no DI injection of
// config), so the environment is loaded directly here once, the same way
// `ConfigModule`'s own provider does it.
const config = loadConfig();

/**
 * `apps/worker` (ADR-011): a NestJS application context, no HTTP server.
 * Processors are thin; business logic lives in `@repo/core` modules
 * (ADR-003, ADR-021).
 */
@Module({
  imports: [
    ConfigModule,
    AppLoggingModule,
    // `@Global()`: provides `DATABASE`/`REDIS` to every module below, no
    // re-import needed (ADR-021 §6).
    CoreInfrastructureModule.forRoot({
      databaseUrl: config.DATABASE_URL,
      redisUrl: config.REDIS_URL,
    }),
    AppBullModule,
    AnalyticsModule.forRoot({ apiKey: config.POSTHOG_API_KEY, host: config.POSTHOG_HOST }),
    StorageModule.forRoot({
      endpoint: config.S3_ENDPOINT,
      region: config.S3_REGION,
      bucket: config.S3_BUCKET,
      accessKeyId: config.S3_ACCESS_KEY_ID,
      secretAccessKey: config.S3_SECRET_ACCESS_KEY,
    }),
    GeocodingModule.forRoot({
      accessToken: config.MAPBOX_GEOCODING_TOKEN,
      permanent: config.MAPBOX_GEOCODING_PERMANENT,
    }),
    // `wildcard`/`delimiter` so listeners can subscribe to `{module}.*`
    // patterns (ADR-021 §3). Events are "same process only" (ADR-021 §3):
    // the worker needs its own instance, separate from `apps/api`'s.
    EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
    // Forwards domain events emitted by the processors below to the mobile
    // app via Redis, after commit (ADR-021 §4).
    RealtimeBridgeModule,
    HeartbeatModule,
    ActivitiesProcessorModule,
    SegmentsProcessorModule,
    SubscriptionsProcessorModule,
  ],
})
export class WorkerModule {}
