import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { BullModule, getQueueToken } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import type { Queue } from "bullmq";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  TRACE_SCHEMA_VERSION,
  activityTraceKey,
  processActivityJobId,
} from "@repo/contracts";
import { ActivitiesModule, ActivitiesService } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule, StorageService } from "@repo/core/storage";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { InMemoryStorage } from "../testing/in-memory-storage.js";
import { BestEffortsController } from "./best-efforts.controller.js";

/** Meters per degree of latitude on the sphere `haversineDistanceM` uses. */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;

/** In-memory bucket: S3 is the only third-party service faked here (ADR-024 §2). */
const storage = new InMemoryStorage();

/** A gzipped trace v2: 2.2 km north at 4 m/s, one point every 10 s. */
function runTrace(start: Date): Uint8Array {
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: Array.from({ length: 56 }, (_, i) => ({
        timestampMs: start.getTime() + i * 10_000,
        lat: 48.85 + (i * 40) / M_PER_DEG_LAT,
        lon: 2.35,
        elevationM: 35,
        horizontalAccuracyM: 5,
      })),
      pauses: [],
    }),
  );
}

/**
 * `DELETE /v1/activities/:id/best-efforts/:distanceM` (ADR-039 §3, §12) over real HTTP, Postgres
 * and Redis (ADR-024 §2). The Medal replays are in the worker's `best-efforts.spec.ts`.
 */
describe("DELETE /v1/activities/:id/best-efforts/:distanceM (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const other = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  const remove = (activityId: string, distance: string, user = author) =>
    fetch(`${baseUrl}/v1/activities/${activityId}/best-efforts/${distance}`, {
      method: "DELETE",
      headers: { "x-test-user": user },
    });
  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;
  const distances = async (activityId: string) =>
    (await app.get(ActivitiesService).getBestEfforts(activityId)).map((effort) => effort.distanceM);

  /** A public 2.2 km run of the author, processed the way `apps/worker` does. */
  async function processedRun(): Promise<string> {
    const activities = app.get(ActivitiesService);
    const id = randomUUID();
    const start = new Date(Date.now() - 3_600_000);
    await activities.create(author, {
      id,
      sportTypeCode: "run",
      title: "Course",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + 550_000).toISOString(),
      visibility: "public",
      isManual: false,
    });
    storage.objects.set(activityTraceKey(author, id), runTrace(start));
    await activities.complete(author, id);
    const job = await app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME)).getJob(processActivityJobId(id));
    await activities.process(job!.data);
    await job!.remove();
    return id;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    bullConnection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
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
        ActivitiesModule,
      ],
      controllers: [BestEffortsController],
      providers: [
        SessionGuard,
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
                : null;
            },
          },
        },
        { provide: APP_PIPE, useClass: ZodValidationPipe },
        { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
        { provide: APP_FILTER, useClass: GlobalExceptionFilter },
      ],
    })
      .overrideProvider(StorageService)
      .useValue(storage)
      .compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);
    for (const id of [author, other]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
  }, 30_000);

  afterAll(async () => {
    // Cascades to the users' activities and Best efforts.
    await sql('delete from "user" where id = any($1)', [[author, other]]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("removes the author's Best effort for good (204), and again without effect", async () => {
    const id = await processedRun();
    expect(await distances(id)).toEqual([400, 1000, 2000]);

    expect((await remove(id, "1000")).status).toBe(204);
    expect(await distances(id)).toEqual([400, 2000]);
    expect((await remove(id, "1000")).status).toBe(204);
    expect(await distances(id)).toEqual([400, 2000]);
  }, 30_000);

  it("answers 404 for another athlete, or a distance without a Best effort", async () => {
    const id = await processedRun();

    const byOther = await remove(id, "1000", other);
    expect(byOther.status).toBe(404);
    expect(await errorCode(byOther)).toBe("best_effort_not_found");
    expect((await remove(id, "5000")).status).toBe(404);
    expect((await remove(randomUUID(), "1000")).status).toBe(404);
    expect(await distances(id)).toEqual([400, 1000, 2000]);
  }, 30_000);

  it("answers 400 for a distance that is not a number", async () => {
    const id = await processedRun();

    expect((await remove(id, "cinq")).status).toBe(400);
  }, 30_000);
});
