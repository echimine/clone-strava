import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplicationContext } from "@nestjs/common";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { AnalyticsModule } from "@repo/core/analytics";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import {
  ObjectTooLargeError,
  StorageModule,
  StorageService,
  type ListedObject,
  type PresignedUrl,
} from "@repo/core/storage";
import { runMigrations } from "@repo/db/migrate";
import { ActivitiesProcessorModule } from "../processors/activities/activities.module.js";
import { AvatarsProcessorModule } from "../processors/avatars/avatars.module.js";
import { BucketSweepProcessorModule } from "../processors/bucket-sweep/bucket-sweep.module.js";

/** Local-dev/test infrastructure (`docker-compose.dev.yml`, ADR-024 §3). */
/** Overridable so parallel worktrees can each use their own database. */
export const TEST_DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? "postgres://strava:strava@127.0.0.1:5432/strava";
export const TEST_REDIS_URL = "redis://127.0.0.1:6379";

/**
 * In-memory stand-in for the bucket: S3 is a third-party network service,
 * the only thing ADR-024 §2 allows to fake in an integration test. Same
 * behaviour as the API's double (`apps/api/src/testing/in-memory-storage.ts`):
 * `lastModified` backdates an object (default: now), `failDeletes` makes
 * every delete throw.
 */
export class InMemoryStorage implements Pick<StorageService, keyof StorageService> {
  readonly objects = new Map<string, Uint8Array>();
  readonly lastModified = new Map<string, Date>();
  failDeletes = false;

  async presignPut(
    key: string,
    _contentType: string,
    options: { contentLength?: number; expiresInSeconds?: number } = {},
  ): Promise<PresignedUrl> {
    const { contentLength, expiresInSeconds = 900 } = options;
    const url = presignedUrl(key, expiresInSeconds);
    if (contentLength !== undefined) {
      url.searchParams.set("Content-Length", String(contentLength));
    }
    return { url: url.toString(), expiresAt: new Date(Date.now() + expiresInSeconds * 1000) };
  }

  async presignGet(key: string, expiresInSeconds = 900): Promise<PresignedUrl> {
    return {
      url: presignedUrl(key, expiresInSeconds).toString(),
      expiresAt: new Date(Date.now() + expiresInSeconds * 1000),
    };
  }

  async headObject(key: string): Promise<{ sizeBytes: number } | undefined> {
    const object = this.objects.get(key);
    return object ? { sizeBytes: object.byteLength } : undefined;
  }

  async getObject(key: string, maxBytes: number): Promise<Uint8Array | undefined> {
    const object = this.objects.get(key);
    if (object && object.byteLength > maxBytes) {
      throw new ObjectTooLargeError(key, maxBytes);
    }
    return object;
  }

  async getObjectRange(
    key: string,
    range: { start: number; end: number },
  ): Promise<Uint8Array | undefined> {
    return this.objects.get(key)?.slice(range.start, range.end + 1);
  }

  async listKeys(prefix: string): Promise<ListedObject[]> {
    return [...this.objects.keys()]
      .filter((key) => key.startsWith(prefix))
      .map((key) => ({ key, lastModified: this.lastModified.get(key) ?? new Date() }));
  }

  async deleteFolder(prefix: string, alsoKeys: readonly string[] = []): Promise<void> {
    const listed = await this.listKeys(prefix);
    this.deleteObjectsNow([...listed.map((object) => object.key), ...alsoKeys]);
  }

  async putObject(key: string, body: Uint8Array): Promise<void> {
    this.objects.set(key, body);
  }

  async deleteObject(key: string): Promise<void> {
    this.deleteObjectsNow([key]);
  }

  async deleteObjects(keys: readonly string[]): Promise<void> {
    this.deleteObjectsNow(keys);
  }

  private deleteObjectsNow(keys: readonly string[]): void {
    if (this.failDeletes) {
      throw new Error("bucket unreachable");
    }
    for (const key of keys) {
      this.objects.delete(key);
      this.lastModified.delete(key);
    }
  }
}

function presignedUrl(key: string, expiresInSeconds: number): URL {
  const url = new URL(`https://bucket.test/${key}`);
  url.searchParams.set("X-Amz-Expires", String(expiresInSeconds));
  url.searchParams.set("X-Amz-Signature", randomUUID());
  return url;
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
 * Boots the activities, bucket-sweep and avatars processors (ADR-024 §4 `test-worker-app.ts`) on
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
      GeocodingModule.forRoot({}),
      EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
      RealtimeBridgeModule,
      ActivitiesProcessorModule,
      BucketSweepProcessorModule,
      AvatarsProcessorModule,
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
