import { Module } from "@nestjs/common";
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { AnalyticsModule } from "@repo/core/analytics";
import { GeocodingModule } from "@repo/core/geocoding";
import { ElevationModule } from "@repo/core/elevation";
import { CoreInfrastructureModule } from "@repo/core/infrastructure";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import { StorageModule } from "@repo/core/storage";
import { AdminModule } from "./admin/admin.module.js";
import { ActivitiesModule } from "./activities/activities.module.js";
import { AuthModule } from "./auth/auth.module.js";
import { FeedModule } from "./feed/feed.module.js";
import { AppBullModule } from "./bull/bull.module.js";
import { GlobalExceptionFilter } from "./common/global-exception.filter.js";
import { ConfigModule } from "./config/config.module.js";
import { loadConfig } from "./config/env.js";
import { HealthModule } from "./health/health.module.js";
import { ItinerariesModule } from "./itineraries/itineraries.module.js";
import { AppLoggingModule } from "./logging/logging.module.js";
import { MeModule } from "./me/me.module.js";
import { RealtimeTokenModule } from "./realtime-token/realtime-token.module.js";
import { WebhooksModule } from "./webhooks/webhooks.module.js";

// `forRoot(...)` dynamic modules below are synchronous (no DI injection of
// config), so the environment is loaded directly here once, the same way
// `ConfigModule`'s own provider does it.
const config = loadConfig();

/**
 * `apps/api` (ADR-009): the only entry point for mobile and backoffice
 * clients. Controllers stay thin and never run a job themselves.
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
    // Processing (the only geocoding user) runs in the worker: no token here (ADR-029).
    GeocodingModule.forRoot({}),
    // Itinerary altitudes (ADR-030 §3): IGN, then Open-Meteo; no key needed.
    ElevationModule.forRoot({}),
    // Forwards domain events emitted here to the mobile app via Redis
    // (ADR-021 §4). `apps/api` currently emits none itself (only the
    // worker does, after job processing), but is loaded per ADR-021 §4
    // ("both processes emit events that may concern the mobile app").
    RealtimeBridgeModule,
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 100 }]),
    // `wildcard`/`delimiter` so listeners can subscribe to `{module}.*` patterns (ADR-021 §3).
    EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
    AuthModule,
    HealthModule,
    MeModule,
    FeedModule,
    ActivitiesModule,
    ItinerariesModule,
    RealtimeTokenModule,
    WebhooksModule,
    AdminModule,
  ],
  providers: [
    { provide: APP_PIPE, useClass: ZodValidationPipe },
    { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
    { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
