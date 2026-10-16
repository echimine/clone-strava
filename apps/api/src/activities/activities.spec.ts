import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { BullModule, getQueueToken } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  ACTIVITY_TRACE_MAX_BYTES,
  PROCESS_ACTIVITY_JOB_NAME,
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
import { ActivitiesController } from "./activities.controller.js";

/** In-memory bucket: S3 is the only third-party service faked here (ADR-024 §2). */
const objects = new Map<string, Uint8Array>();
const storage = {
  head: async (key: string) => (objects.has(key) ? { sizeBytes: objects.get(key)!.byteLength } : undefined),
  getObject: async (key: string) => objects.get(key),
  deleteObject: async (key: string) => {
    objects.delete(key);
  },
  presignPut: async (key: string) => ({
    url: `https://bucket.test/${key}?sig=${randomUUID()}`,
    expiresAt: new Date(Date.now() + 900_000),
  }),
};

/** A gzipped trace v2 (ADR-031 §12): 10 minutes of running, one point per minute, ~111 m apart. */
function runTrace(points = 11): Uint8Array {
  const start = Date.now() - 3_600_000;
  const trace = {
    schemaVersion: TRACE_SCHEMA_VERSION,
    points: Array.from({ length: points }, (_, i) => ({
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
 * `/v1/activities` creation flow (ADR-019 §1, §2, §4) and the author's
 * `GET /v1/activities/:id` (ADR-031 §13) over real HTTP, Postgres and
 * Redis (ADR-024 §2). Sessions come from `x-test-user` through a fake
 * `AuthService` (see `activity-imports.spec.ts`).
 */
describe("/v1/activities (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const userA = randomUUID();
  const userB = randomUUID();
  const inactiveSport = `retired-${randomUUID().slice(0, 8)}`;

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  const activitiesQueue = () => app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME));

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/activities${path}`, {
      method: init.method ?? "POST",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  /** Loose view of a JSON response body, enough for assertions. */
  type Json = {
    activity: { id: string; processingStatus: string };
    upload?: { uploadUrl: string; expiresAt: string };
    error: { code: string; details?: Array<{ field: string }> };
  };
  const json = async (response: Response) => (await response.json()) as Json;

  /** A 30-minute run recorded an hour ago. */
  const body = (id: string, overrides: Record<string, unknown> = {}) => ({
    id,
    sportTypeCode: "run",
    title: "Course du matin",
    startedAt: new Date(Date.now() - 3_600_000).toISOString(),
    endedAt: new Date(Date.now() - 1_800_000).toISOString(),
    visibility: "followers",
    isManual: false,
    distanceM: 5012.4,
    movingTimeS: 1750,
    elapsedTimeS: 1800,
    ...overrides,
  });

  /**
   * Creates, uploads and completes an activity of `userA`, then runs its
   * `process-activity` job the way `apps/worker` does (same
   * `ActivitiesService.process` entry point), and drops the finished job.
   */
  async function runThroughWorker(trace: Uint8Array): Promise<string> {
    const id = randomUUID();
    await call("", userA, { body: body(id) });
    objects.set(activityTraceKey(userA, id), trace);
    expect((await call(`/${id}/complete`, userA)).status).toBe(202);
    const job = await activitiesQueue().getJob(processActivityJobId(id));
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
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? {
                    userId,
                    email: `${userId}@test.local`,
                    name: "Test",
                    role: "user",
                    twoFactorEnabled: false,
                  }
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

    for (const id of [userA, userB]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
    await sql(
      "insert into sports.sport_type (code, category, icon_name, is_active) values ($1, 'test', 'figure.run', false)",
      [inactiveSport],
    );
  }, 30_000);

  afterAll(async () => {
    // Cascades to the users' activities.
    await sql('delete from "user" where id = any($1)', [[userA, userB]]);
    await sql("delete from sports.sport_type where code = $1", [inactiveSport]);
    await app?.close();
    await bullConnection?.quit();
  });

  describe("POST /v1/activities", () => {
    it("creates a pending activity (201) with a 15-minute upload URL for its trace", async () => {
      const id = randomUUID();
      const response = await call("", userA, { body: body(id) });
      expect(response.status).toBe(201);
      const created = await json(response);
      expect(created.activity).toMatchObject({ id, processingStatus: "pending", visibility: "followers" });
      expect(created.upload?.uploadUrl).toContain(activityTraceKey(userA, id));
      const expiresInMs = new Date(created.upload!.expiresAt).getTime() - Date.now();
      expect(expiresInMs).toBeGreaterThan(14 * 60_000);
      expect(expiresInMs).toBeLessThanOrEqual(15 * 60_000);
    });

    it("replays the same call on a pending activity (200) with a new upload URL", async () => {
      const id = randomUUID();
      const first = await json(await call("", userA, { body: body(id) }));
      const replay = await call("", userA, { body: body(id) });
      expect(replay.status).toBe(200);
      const replayed = await json(replay);
      expect(replayed.activity).toMatchObject({ id, processingStatus: "pending" });
      expect(replayed.upload?.uploadUrl).toContain(activityTraceKey(userA, id));
      expect(replayed.upload?.uploadUrl).not.toBe(first.upload?.uploadUrl);
    });

    it("refuses an id that belongs to another athlete (409), without an upload URL", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      const response = await call("", userB, { body: body(id) });
      expect(response.status).toBe(409);
      const conflict = await json(response);
      expect(conflict.error.code).toBe("id_conflict");
      expect(conflict.upload).toBeUndefined();
    });

    it.each([
      ["an inactive sport", () => ({ sportTypeCode: inactiveSport }), "sportTypeCode"],
      ["an unknown sport", () => ({ sportTypeCode: "quidditch" }), "sportTypeCode"],
      [
        "an end not after the start",
        () => ({ startedAt: "2026-10-01T08:00:00.000Z", endedAt: "2026-10-01T08:00:00.000Z" }),
        "endedAt",
      ],
      [
        "a duration below the sport's minimum",
        () => ({ startedAt: "2026-10-01T08:00:00.000Z", endedAt: "2026-10-01T08:00:59.000Z" }),
        "endedAt",
      ],
      ["a moving time below the sport's minimum", () => ({ movingTimeS: 59 }), "movingTimeS"],
      ["a distance below the sport's minimum", () => ({ distanceM: 99.9 }), "distanceM"],
    ])("refuses %s (422) and creates nothing", async (_case, overrides, field) => {
      const id = randomUUID();
      const response = await call("", userA, { body: body(id, overrides()) });
      expect(response.status).toBe(422);
      const { error } = await json(response);
      expect(error.code).toBe("validation_error");
      expect(error.details?.map((detail) => detail.field)).toEqual([field]);
      expect(await sql("select id from activities.activity where id = $1", [id])).toEqual([]);
    });

    it.each([
      ["right at the sport's minimums", { movingTimeS: 60, distanceM: 100 }],
      ["without provisional values", { movingTimeS: undefined, distanceM: undefined, elapsedTimeS: undefined }],
    ])("accepts an activity %s (201)", async (_case, overrides) => {
      const response = await call("", userA, { body: body(randomUUID(), overrides) });
      expect(response.status).toBe(201);
    });
  });

  describe("GET /v1/activities/:id", () => {
    type Detail = {
      id: string;
      title: string;
      visibility: string;
      processingStatus: string;
      processingError?: string;
      stats: { distanceM: number; movingTimeS: number; elapsedTimeS: number } | null;
    };
    const get = async (id: string, user = userA) => {
      const response = await call(`/${id}`, user, { method: "GET" });
      return { status: response.status, detail: (await response.json()) as Detail };
    };

    it("shows the author a pending activity, without official values yet", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      const { status, detail } = await get(id);
      expect(status).toBe(200);
      expect(detail).toMatchObject({
        id,
        title: "Course du matin",
        visibility: "followers",
        processingStatus: "pending",
        stats: null,
      });
      expect(detail.processingError).toBeUndefined();
    });

    it("gives the official values once processed, not the provisional ones", async () => {
      const id = await processedActivity();
      const { status, detail } = await get(id);
      expect(status).toBe(200);
      expect(detail.processingStatus).toBe("processed");
      // 10 legs of 0.001° of latitude (~111.2 m each), one minute apart.
      expect(detail.stats?.distanceM).toBeCloseTo(1112, -1);
      expect(detail.stats?.elapsedTimeS).toBe(600);
      expect(detail.stats?.movingTimeS).toBe(600);
    });

    it("returns processingError after the worker failed the activity", async () => {
      const id = await failedActivity();
      const { status, detail } = await get(id);
      expect(status).toBe(200);
      expect(detail).toMatchObject({
        processingStatus: "failed",
        processingError: "invalid_trace",
        stats: null,
      });
    });

    it("answers 404 to another athlete for a followers activity without follow (ADR-033 §2)", async () => {
      const id = await processedActivity();
      expect((await get(id, userB)).status).toBe(404);
      expect((await get(randomUUID())).status).toBe(404);
    });
  });

  describe("DELETE /v1/activities/:id", () => {
    const remove = (id: string, user = userA) => call(`/${id}`, user, { method: "DELETE" });
    const exists = async (id: string) =>
      (await sql("select id from activities.activity where id = $1", [id])).length > 0;

    it("deletes the author's pending activity for good (204), its trace with it", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      objects.set(activityTraceKey(userA, id), runTrace());
      const response = await remove(id);
      expect(response.status).toBe(204);
      expect(await exists(id)).toBe(false);
      expect(objects.has(activityTraceKey(userA, id))).toBe(false);
      expect((await call(`/${id}`, userA, { method: "GET" })).status).toBe(404);
    });

    it("deletes a failed activity (204)", async () => {
      const id = await failedActivity();
      expect((await remove(id)).status).toBe(204);
      expect(await exists(id)).toBe(false);
    });

    it("refuses a processing or processed activity (409) and keeps it", async () => {
      const processing = randomUUID();
      await call("", userA, { body: body(processing) });
      objects.set(activityTraceKey(userA, processing), runTrace());
      await call(`/${processing}/complete`, userA);
      const processed = await processedActivity();
      for (const id of [processing, processed]) {
        const response = await remove(id);
        expect(response.status).toBe(409);
        expect((await json(response)).error.code).toBe("not_deletable");
        expect(await exists(id)).toBe(true);
      }
    });

    it("answers 404 to another athlete and for an unknown id", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      expect((await remove(id, userB)).status).toBe(404);
      expect(await exists(id)).toBe(true);
      expect((await remove(randomUUID())).status).toBe(404);
    });
  });

  describe("POST /v1/activities/:id/upload-url", () => {
    it("renews the upload URL of a pending activity (200)", async () => {
      const id = randomUUID();
      const first = await json(await call("", userA, { body: body(id) }));
      const response = await call(`/${id}/upload-url`, userA);
      expect(response.status).toBe(200);
      const renewed = (await response.json()) as { uploadUrl: string; expiresAt: string };
      expect(renewed.uploadUrl).toContain(activityTraceKey(userA, id));
      expect(renewed.uploadUrl).not.toBe(first.upload?.uploadUrl);
      expect(new Date(renewed.expiresAt).getTime()).toBeGreaterThan(Date.now() + 14 * 60_000);
    });

    it("refuses once the trace was handed over (409 not_pending)", async () => {
      const id = await processedActivity();
      const response = await call(`/${id}/upload-url`, userA);
      expect(response.status).toBe(409);
      expect((await json(response)).error.code).toBe("not_pending");
    });

    it("answers 404 to another athlete", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      expect((await call(`/${id}/upload-url`, userB)).status).toBe(404);
    });
  });

  describe("POST /v1/activities/:id/complete", () => {
    it("refuses to complete before the trace is in the bucket (409 trace_missing)", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      const response = await call(`/${id}/complete`, userA);
      expect(response.status).toBe(409);
      expect((await json(response)).error.code).toBe("trace_missing");
    });

    it("refuses a trace over the size limit (409 trace_too_large) and leaves the activity pending", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      objects.set(activityTraceKey(userA, id), new Uint8Array(ACTIVITY_TRACE_MAX_BYTES + 1));
      const response = await call(`/${id}/complete`, userA);
      objects.delete(activityTraceKey(userA, id));
      expect(response.status).toBe(409);
      expect((await json(response)).error.code).toBe("trace_too_large");
      expect((await json(await call("", userA, { body: body(id) }))).activity.processingStatus).toBe(
        "pending",
      );
    });

    it("accepts an uploaded trace (202): processing, one process-activity job, replays change nothing", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      objects.set(activityTraceKey(userA, id), runTrace());

      const accepted = await call(`/${id}/complete`, userA);
      expect(accepted.status).toBe(202);
      expect((await json(accepted)).activity).toMatchObject({ id, processingStatus: "processing" });
      const job = await activitiesQueue().getJob(processActivityJobId(id));
      expect(job?.name).toBe(PROCESS_ACTIVITY_JOB_NAME);
      expect(job?.data).toMatchObject({ activityId: id, userId: userA });

      const replay = await call(`/${id}/complete`, userA);
      expect(replay.status).toBe(202);
      expect((await json(replay)).activity.processingStatus).toBe("processing");
      expect((await activitiesQueue().getJob(processActivityJobId(id)))?.timestamp).toBe(job?.timestamp);
    });

    it("treats complete on a processed activity as a replay (202, no new job); its upload is over", async () => {
      const id = await processedActivity();

      const replay = await call(`/${id}/complete`, userA);
      expect(replay.status).toBe(202);
      expect((await json(replay)).activity.processingStatus).toBe("processed");
      expect(await activitiesQueue().getJob(processActivityJobId(id))).toBeUndefined();

      const created = await call("", userA, { body: body(id) });
      expect(created.status).toBe(200);
      const replayed = await json(created);
      expect(replayed.activity.processingStatus).toBe("processed");
      expect(replayed.upload).toBeUndefined();
    });

    it("refuses to complete a failed activity (409)", async () => {
      const id = await failedActivity();
      const response = await call(`/${id}/complete`, userA);
      expect(response.status).toBe(409);
      expect((await json(response)).error.code).toBe("activity_failed");
      expect(await activitiesQueue().getJob(processActivityJobId(id))).toBeUndefined();
    });

    it("answers 404 to another athlete", async () => {
      const id = randomUUID();
      await call("", userA, { body: body(id) });
      objects.set(activityTraceKey(userA, id), runTrace());
      expect((await call(`/${id}/complete`, userB)).status).toBe(404);
    });
  });
});
