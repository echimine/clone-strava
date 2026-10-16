import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import jwt from "jsonwebtoken";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule } from "@repo/core/storage";
import {
  REALTIME_GRANT_AUDIENCE,
  REALTIME_TOKEN_AUDIENCE,
  REALTIME_TOKEN_ISSUER,
  activityTopic,
  userTopic,
} from "@repo/realtime";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { CONFIG } from "../config/env.js";
import { RealtimeGrantsController } from "./realtime-grants.controller.js";

const SECRET = "grants-spec-secret-at-least-32-characters";

/**
 * `POST /v1/realtime/grants` over real HTTP and Postgres (ADR-034 §5): a
 * subscription grant for `activity:{id}`, only for an Activity the viewer
 * can see.
 */
describe("POST /v1/realtime/grants (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const viewer = randomUUID();

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function insertActivity(userId: string, visibility: string) {
    const id = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now() - interval '2 hours', now() - interval '1 hour', $3, 'processed')`,
      [id, userId, visibility],
    );
    return id;
  }

  function requestGrant(user: string, body: unknown) {
    return fetch(`${baseUrl}/v1/realtime/grants`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: JSON.stringify(body),
    });
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
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
      controllers: [RealtimeGrantsController],
      providers: [
        SessionGuard,
        { provide: CONFIG, useValue: { REALTIME_TOKEN_SECRET: SECRET } },
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
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    await app.listen(0);
    const address = app.getHttpServer().address();
    baseUrl = `http://127.0.0.1:${typeof address === "object" && address ? address.port : 0}`;

    for (const id of [author, viewer]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
  }, 30_000);

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [[author, viewer]]);
    await app.close();
    await bullConnection.quit();
  });

  it("grants activity:{id} for an Activity the viewer can see", async () => {
    const activityId = await insertActivity(author, "public");
    const topic = activityTopic(activityId);

    const response = await requestGrant(viewer, { topic });

    expect(response.status).toBe(200);
    const body = (await response.json()) as { grant: string; expiresInS: number };
    expect(body.expiresInS).toBe(60);
    const claims = jwt.verify(body.grant, SECRET, {
      algorithms: ["HS256"],
      issuer: REALTIME_TOKEN_ISSUER,
      audience: REALTIME_GRANT_AUDIENCE,
    }) as jwt.JwtPayload;
    expect(claims).toMatchObject({ sub: viewer, topic });
    expect(claims.exp! - claims.iat!).toBe(60);
    // The distinct audience keeps it from ever opening a connection.
    expect(() => jwt.verify(body.grant, SECRET, { audience: REALTIME_TOKEN_AUDIENCE })).toThrow();
  });

  it("grants the author their own private Activity", async () => {
    const activityId = await insertActivity(author, "private");
    expect((await requestGrant(author, { topic: activityTopic(activityId) })).status).toBe(200);
  });

  it("answers 404 for an Activity the viewer cannot see or that does not exist", async () => {
    const privateActivity = await insertActivity(author, "private");
    const hidden = await requestGrant(viewer, { topic: activityTopic(privateActivity) });
    expect(hidden.status).toBe(404);
    expect(await errorCode(hidden)).toBe("activity_not_found");

    expect((await requestGrant(viewer, { topic: activityTopic(randomUUID()) })).status).toBe(404);
  });

  it("answers 422 for a topic it does not grant", async () => {
    const invalid = [
      userTopic(viewer),
      "activity:not-a-uuid",
      "activity:",
      `${activityTopic(randomUUID())}x`,
      // The bridge publishes on the lowercase id: an uppercase topic would never receive anything.
      activityTopic(randomUUID().toUpperCase()),
    ];
    for (const topic of invalid) {
      const response = await requestGrant(viewer, { topic });
      expect(response.status, topic).toBe(422);
      expect(await errorCode(response)).toBe("validation_error");
    }
    expect((await requestGrant(viewer, {})).status).toBe(422);
  });

  it("answers 401 without a session", async () => {
    const response = await fetch(`${baseUrl}/v1/realtime/grants`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ topic: activityTopic(randomUUID()) }),
    });
    expect(response.status).toBe(401);
  });
});
