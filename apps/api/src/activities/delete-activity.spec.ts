import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { BullModule, getQueueToken } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitter2, EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi, type MockInstance } from "vitest";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  ACTIVITY_DELETED_EVENT,
  TRACE_SCHEMA_VERSION,
  activityTraceKey,
  processActivityJobId,
} from "@repo/contracts";
import { ActivitiesModule, ActivitiesService, PermanentProcessingError } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule, StorageService } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { ActivitiesController } from "./activities.controller.js";

/** In-memory bucket: S3 is the only third-party service faked here (ADR-024 §2). */
const objects = new Map<string, Uint8Array>();
/** When set, every `deleteObject` fails, like an unreachable bucket. */
let bucketDown = false;
const storage = {
  head: async (key: string) => (objects.has(key) ? { sizeBytes: objects.get(key)!.byteLength } : undefined),
  getObject: async (key: string) => objects.get(key),
  deleteObject: async (key: string) => {
    if (bucketDown) throw new Error("bucket unreachable");
    objects.delete(key);
  },
  presignPut: async (key: string) => ({
    url: `https://bucket.test/${key}?sig=${randomUUID()}`,
    expiresAt: new Date(Date.now() + 900_000),
  }),
};

/** A gzipped trace v2 (ADR-031 §12): 10 minutes of running, one point per minute, ~111 m apart. */
function runTrace(): Uint8Array {
  const start = Date.now() - 3_600_000;
  const trace = {
    schemaVersion: TRACE_SCHEMA_VERSION,
    points: Array.from({ length: 11 }, (_, i) => ({
      timestampMs: start + i * 60_000,
      lat: 48.85 + i * 0.001,
      lon: 2.35,
      elevationM: 35 + i,
      horizontalAccuracyM: 5,
    })),
    pauses: [],
  };
  return gzipSync(JSON.stringify(trace));
}

/**
 * `DELETE /v1/activities/:id` (ADR-031 §13, ADR-033 §6) over real HTTP,
 * Postgres and Redis (ADR-024 §2). Sessions come from `x-test-user`
 * through a fake `AuthService` (see `activity-imports.spec.ts`). The
 * imported case and re-importing the same file are in the worker's
 * `import-activity.spec.ts`, which runs the real import pipeline.
 */
describe("DELETE /v1/activities/:id (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  let emit: MockInstance<EventEmitter2["emit"]>;
  const userA = randomUUID();
  const userB = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/activities${path}`, {
      method: init.method ?? "POST",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }
  const remove = (id: string, user = userA) => call(`/${id}`, user, { method: "DELETE" });
  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;
  const exists = async (id: string) =>
    (await sql("select id from activities.activity where id = $1", [id])).length > 0;

  /** A 30-minute run of `userA` recorded an hour ago, `public` so that `userB` sees it once processed. */
  const body = (id: string) => ({
    id,
    sportTypeCode: "run",
    title: "Course du matin",
    startedAt: new Date(Date.now() - 3_600_000).toISOString(),
    endedAt: new Date(Date.now() - 1_800_000).toISOString(),
    visibility: "public",
    isManual: false,
    distanceM: 5012.4,
    movingTimeS: 1750,
    elapsedTimeS: 1800,
  });

  /** Creates, uploads and completes an activity of `userA`: it is then `processing`. */
  async function processingActivity(trace: Uint8Array): Promise<string> {
    const id = randomUUID();
    await call("", userA, { body: body(id) });
    objects.set(activityTraceKey(userA, id), trace);
    expect((await call(`/${id}/complete`, userA)).status).toBe(202);
    return id;
  }

  /** Runs the `process-activity` job the way `apps/worker` does, and drops the finished job. */
  async function runThroughWorker(trace: Uint8Array): Promise<string> {
    const id = await processingActivity(trace);
    const queue = app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME));
    const job = await queue.getJob(processActivityJobId(id));
    await app
      .get(ActivitiesService)
      .process(job!.data)
      .catch((error: unknown) => {
        if (!(error instanceof PermanentProcessingError)) throw error;
      });
    await job!.remove();
    return id;
  }
  const processedActivity = () => runThroughWorker(runTrace());
  /** Unreadable trace: the worker fails it permanently with `invalid_trace` (ADR-019 §6). */
  const failedActivity = () => runThroughWorker(new TextEncoder().encode("not gzip"));

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
        EngagementModule,
        UsersModule,
      ],
      controllers: [ActivitiesController],
      providers: [
        SessionGuard,
        FeedAssembler,
        AthleteIdentities,
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
                : null;
            },
            getPublicIdentities: async () => [],
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
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;
    emit = vi.spyOn(app.get(EventEmitter2), "emit");

    for (const id of [userA, userB]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
  }, 30_000);

  afterEach(() => {
    bucketDown = false;
    emit.mockClear();
  });

  afterAll(async () => {
    // Cascades to the users' activities.
    await sql('delete from "user" where id = any($1)', [[userA, userB]]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("deletes the author's processed activity for good (204), its trace with it, then 404", async () => {
    const id = await processedActivity();

    const response = await remove(id);

    expect(response.status).toBe(204);
    expect(await exists(id)).toBe(false);
    expect(objects.has(activityTraceKey(userA, id))).toBe(false);
    expect(emit).toHaveBeenCalledWith(ACTIVITY_DELETED_EVENT, { activityId: id, userId: userA });
    expect((await call(`/${id}`, userA, { method: "GET" })).status).toBe(404);
    expect((await remove(id)).status).toBe(404);
  });

  it("deletes the author's pending activity (204), its trace with it", async () => {
    const id = randomUUID();
    await call("", userA, { body: body(id) });
    objects.set(activityTraceKey(userA, id), runTrace());

    expect((await remove(id)).status).toBe(204);
    expect(await exists(id)).toBe(false);
    expect(objects.has(activityTraceKey(userA, id))).toBe(false);
  });

  it("deletes a failed activity (204)", async () => {
    const id = await failedActivity();
    expect((await remove(id)).status).toBe(204);
    expect(await exists(id)).toBe(false);
  });

  it("refuses an activity the worker is processing (409 not_deletable) and keeps it", async () => {
    const id = await processingActivity(runTrace());

    const response = await remove(id);

    expect(response.status).toBe(409);
    expect(await errorCode(response)).toBe("not_deletable");
    expect(await exists(id)).toBe(true);
    expect(emit).not.toHaveBeenCalledWith(ACTIVITY_DELETED_EVENT, expect.anything());
  });

  it("answers 403 not_activity_author to another athlete who sees the activity, and keeps it", async () => {
    const id = await processedActivity();

    const response = await remove(id, userB);

    expect(response.status).toBe(403);
    expect(await errorCode(response)).toBe("not_activity_author");
    expect(await exists(id)).toBe(true);
  });

  it("answers 404 to another athlete who cannot see the activity, and for an unknown id", async () => {
    const id = randomUUID();
    await call("", userA, { body: body(id) });

    expect((await remove(id, userB)).status).toBe(404);
    expect(await exists(id)).toBe(true);
    expect((await remove(randomUUID())).status).toBe(404);
  });

  it("deletes the activity's kudos and comments with it", async () => {
    const id = await processedActivity();
    await sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [userB, id]);
    await sql("insert into engagement.comment (activity_id, user_id, body) values ($1, $2, 'Bravo')", [id, userB]);

    expect((await remove(id)).status).toBe(204);

    expect(await sql("select 1 from engagement.kudos where activity_id = $1", [id])).toHaveLength(0);
    expect(await sql("select 1 from engagement.comment where activity_id = $1", [id])).toHaveLength(0);
  });

  it("still answers 204 when the bucket cannot delete the trace", async () => {
    const id = await processedActivity();
    bucketDown = true;

    const response = await remove(id);

    expect(response.status).toBe(204);
    expect(await exists(id)).toBe(false);
    expect(emit).toHaveBeenCalledWith(ACTIVITY_DELETED_EVENT, { activityId: id, userId: userA });
  });
});
