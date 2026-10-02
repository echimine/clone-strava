import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { activityImportSourceKey } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule, StorageService } from "@repo/core/storage";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { ActivityImportsController } from "./activity-imports.controller.js";

/** In-memory bucket: S3 is the only third-party service faked here (ADR-024 §2). */
const objects = new Map<string, Uint8Array>();
const storage = {
  head: async (key: string) => (objects.has(key) ? { sizeBytes: objects.get(key)!.byteLength } : undefined),
  presignPut: async (key: string) => ({
    url: `https://bucket.test/${key}`,
    expiresAt: new Date(Date.now() + 900_000),
  }),
};

/**
 * `/v1/activity-imports` over real HTTP, Postgres and Redis (ADR-024 §2
 * integration tier). Sessions come from `x-test-user` through a fake
 * `AuthService` behind the real `SessionGuard`: Better Auth itself is
 * covered by `auth-flows.spec.ts`, and its sign-up rate limit would make
 * real sessions flaky here.
 */
describe("/v1/activity-imports (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let redis: Redis;
  let bullConnection: Redis;
  const userA = randomUUID();
  const userB = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1/activity-imports${path}`, {
      method: init.method ?? "POST",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  /** Loose view of a JSON response body, enough for assertions. */
  type Json = {
    import: { id: string; status: string; format: string };
    upload?: { uploadUrl: string };
    error: { code: string; details: Array<{ field: string }> };
    items: Array<{ id: string }>;
  };
  const json = async (response: Response) => (await response.json()) as Json;

  const body = (id: string) => ({ id, format: "gpx", fileName: "run.gpx", sizeBytes: 1000 });

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
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        ActivitiesModule,
      ],
      controllers: [ActivityImportsController],
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
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;

    redis = new Redis(TEST_REDIS_URL);
    for (const id of [userA, userB]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
  }, 30_000);

  beforeEach(async () => {
    await redis.del(`ratelimit:activity-imports:${userA}`, `ratelimit:activity-imports:${userB}`);
  });

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [[userA, userB]]);
    await app?.close();
    await Promise.allSettled([redis?.quit(), bullConnection?.quit()]);
  });

  it("creates an import (201), then replays it (200) with a new upload URL", async () => {
    const id = randomUUID();
    const first = await call("", userA, { body: body(id) });
    expect(first.status).toBe(201);
    const created = await json(first);
    expect(created.import).toMatchObject({ id, status: "pending", format: "gpx" });
    expect(created.upload?.uploadUrl).toContain(activityImportSourceKey(userA, id, "gpx"));

    const replay = await call("", userA, { body: body(id) });
    expect(replay.status).toBe(200);
    expect((await json(replay)).upload).toBeDefined();
  });

  it("refuses an id owned by another user (409) and hides it from them (404)", async () => {
    const id = randomUUID();
    await call("", userA, { body: body(id) });
    expect((await call("", userB, { body: body(id) })).status).toBe(409);
    expect((await call(`/${id}`, userB, { method: "GET" })).status).toBe(404);
  });

  it("validates the body (422)", async () => {
    const response = await call("", userA, {
      body: { ...body(randomUUID()), fileName: "run.fit", sizeBytes: 100 * 1024 * 1024 },
    });
    expect(response.status).toBe(422);
    const { error } = await json(response);
    expect(error.details.map((detail) => detail.field).sort()).toEqual([
      "fileName",
      "sizeBytes",
    ]);
  });

  it("requires the uploaded file before completing (409 file_missing), then accepts it (202)", async () => {
    const id = randomUUID();
    await call("", userA, { body: body(id) });

    const missing = await call(`/${id}/complete`, userA);
    expect(missing.status).toBe(409);
    expect((await json(missing)).error.code).toBe("file_missing");

    objects.set(activityImportSourceKey(userA, id, "gpx"), new Uint8Array(1000));
    const accepted = await call(`/${id}/complete`, userA);
    expect(accepted.status).toBe(202);
    expect((await json(accepted)).import.status).toBe("processing");

    // Replayed `complete`: still 202, and no upload URL renewal any more.
    expect((await call(`/${id}/complete`, userA)).status).toBe(202);
    expect((await call(`/${id}/upload-url`, userA)).status).toBe(409);

    const list = await json(await call("?status=processing", userA, { method: "GET" }));
    expect(list.items.map((item) => item.id)).toContain(id);
  });

  it("rate-limits new imports (429 with Retry-After), not replays", async () => {
    await redis.set(`ratelimit:activity-imports:${userB}`, "30", "EX", 600);
    const limited = await call("", userB, { body: body(randomUUID()) });
    expect(limited.status).toBe(429);
    expect(Number(limited.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await json(limited)).error.code).toBe("rate_limited");
  });

  it("rejects unauthenticated calls (401)", async () => {
    const response = await fetch(`${baseUrl}/v1/activity-imports`, { method: "GET" });
    expect(response.status).toBe(401);
  });
});
