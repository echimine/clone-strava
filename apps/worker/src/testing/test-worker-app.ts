import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplicationContext } from "@nestjs/common";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { AnalyticsModule } from "@repo/core/analytics";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import { StorageModule, StorageService } from "@repo/core/storage";
import { runMigrations } from "@repo/db/migrate";
import { ActivitiesProcessorModule } from "../processors/activities/activities.module.js";

/** Local-dev/test infrastructure (`docker-compose.dev.yml`, ADR-024 §3). */
export const TEST_DATABASE_URL = "postgres://strava:strava@127.0.0.1:5432/strava";
export const TEST_REDIS_URL = "redis://127.0.0.1:6379";

/**
 * In-memory stand-in for the bucket: S3 is a third-party network service,
 * the only thing ADR-024 §2 allows to fake in an integration test.
 */
export class InMemoryStorage implements Pick<StorageService, "head" | "getObject" | "putObject" | "presignPut"> {
  readonly objects = new Map<string, Uint8Array>();

  async head(key: string) {
    const object = this.objects.get(key);
    return object ? { sizeBytes: object.byteLength } : undefined;
  }

  async getObject(key: string) {
    return this.objects.get(key);
  }

  async putObject(key: string, body: Uint8Array) {
    this.objects.set(key, body);
  }

  async presignPut(key: string) {
    return { url: `https://bucket.test/${key}`, expiresAt: new Date(Date.now() + 900_000) };
  }
}

export interface TestWorkerApp {
  app: INestApplicationContext;
  db: Database;
  storage: InMemoryStorage;
  /** Messages published on the realtime Redis channel during the test. */
  realtimeMessages: Array<{ topics: string[]; envelope: { t: string; data: Record<string, unknown> } }>;
  close(): Promise<void>;
}

/**
 * Boots the activities processors (ADR-024 §4 `test-worker-app.ts`) on
 * the real dev Postgres and Redis, with a random BullMQ prefix so the
 * queues never mix with a dev worker running on the same Redis.
 */
export async function bootstrapTestWorkerApp(): Promise<TestWorkerApp> {
  await runMigrations(TEST_DATABASE_URL);

  const storage = new InMemoryStorage();
  const bullConnection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
  const moduleRef = await Test.createTestingModule({
    imports: [
      CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
      BullModule.forRoot({ connection: bullConnection, prefix: `test-${randomUUID()}` }),
      AnalyticsModule.forRoot({}),
      StorageModule.forRoot({
        endpoint: "https://bucket.test",
        region: "test",
        bucket: "test",
        accessKeyId: "test",
        secretAccessKey: "test",
      }),
      EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
      RealtimeBridgeModule,
      ActivitiesProcessorModule,
    ],
  })
    .overrideProvider(StorageService)
    .useValue(storage)
    .compile();

  const realtimeMessages: TestWorkerApp["realtimeMessages"] = [];
  const subscriber = new Redis(TEST_REDIS_URL);
  await subscriber.subscribe("realtime:events");
  subscriber.on("message", (_channel, message) => realtimeMessages.push(JSON.parse(message)));

  const app = await moduleRef.init();
  return {
    app,
    db: app.get<Database>(DATABASE),
    storage,
    realtimeMessages,
    async close() {
      await app.close();
      await Promise.allSettled([subscriber.quit(), bullConnection.quit()]);
    },
  };
}

/** Polls `check` until it returns a value or the timeout expires. */
export async function waitFor<T>(check: () => Promise<T | undefined>, timeoutMs = 15_000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value !== undefined) {
      return value;
    }
    if (Date.now() > deadline) {
      throw new Error("waitFor: timed out");
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
