import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { activityDetailSchema, type ActivityDetail } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { ActivitiesController } from "./activities.controller.js";

/**
 * `GET /v1/activities/:id` for every viewer who can see the Activity (ADR-033 §2) over real
 * HTTP and Postgres (ADR-024 §2). Sessions come from `x-test-user` through a fake
 * `AuthService` (see `feed.spec.ts`).
 */
describe("GET /v1/activities/:id (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const follower = randomUUID();
  const pendingFollower = randomUUID();
  const stranger = randomUUID();
  const users = [author, follower, pendingFollower, stranger];
  const ids = {
    publicProcessed: randomUUID(),
    followersProcessed: randomUUID(),
    privateProcessed: randomUUID(),
    pending: randomUUID(),
    processing: randomUUID(),
    failed: randomUUID(),
  };
  const startedAt = new Date("2026-10-12T07:30:00.000Z");
  const updatedAt = new Date("2026-10-13T18:00:00.000Z");

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function get(id: string, user: string) {
    const response = await fetch(`${baseUrl}/v1/activities/${id}`, { headers: { "x-test-user": user } });
    return { status: response.status, body: (await response.json()) as ActivityDetail & { error: { code: string } } };
  }

  async function insertActivity(
    id: string,
    options: { visibility?: string; status?: string; error?: string; withResults?: boolean } = {},
  ) {
    await sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility, processing_status, processing_error, updated_at)
       values ($1, $2, 'run', 'Sortie au lac', 'Belle lumière', $3, $4, $5, $6, $7, $8)`,
      [id, author, startedAt, new Date(startedAt.getTime() + 3_600_000), options.visibility ?? "public",
        options.status ?? "processed", options.error ?? null, updatedAt],
    );
    if (options.withResults ?? true) {
      await sql(
        `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m,
           avg_speed_ms, max_speed_ms, avg_heart_rate, max_heart_rate, calories)
         values ($1, 10234.5, 3120, 3300, 245, 3.28, 5.5, 152, 181, 812)`,
        [id],
      );
      await sql(
        `insert into activities.activity_track (activity_id, map_polyline, location_name)
         values ($1, '_p~iF~ps|U', 'Annecy, Haute-Savoie')`,
        [id],
      );
    }
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
                ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
                : null;
            },
            getPublicIdentities: async (userIds: string[]) =>
              sql('select id as "userId", name, image from "user" where id = any($1)', [userIds]),
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

    for (const [index, id] of users.entries()) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, `User ${index}`, `${id}@test.local`]);
    }
    await sql(
      "insert into users.user_profile (user_id, first_name, last_name, avatar_url) values ($1, 'Camille', 'Martin', 'https://cdn.test/a.png')",
      [author],
    );
    await sql(
      "insert into social.follow (follower_id, followee_id, status) values ($1, $3, 'accepted'), ($2, $3, 'pending')",
      [follower, pendingFollower, author],
    );

    await insertActivity(ids.publicProcessed);
    await insertActivity(ids.followersProcessed, { visibility: "followers" });
    await insertActivity(ids.privateProcessed, { visibility: "private" });
    await insertActivity(ids.pending, { status: "pending", withResults: false });
    await insertActivity(ids.processing, { status: "processing", withResults: false });
    await insertActivity(ids.failed, { status: "failed", error: "invalid_trace", withResults: false });
    await sql("insert into engagement.kudos (user_id, activity_id) values ($1, $3), ($2, $3)", [
      stranger,
      follower,
      ids.publicProcessed,
    ]);
    await sql("insert into engagement.comment (user_id, activity_id, body) values ($1, $2, 'Bravo')", [
      follower,
      ids.publicProcessed,
    ]);
  }, 30_000);

  afterAll(async () => {
    // Cascades to the users' activities, kudos and comments.
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("gives another athlete a public processed Activity in full: author, map, place, stats, engagement", async () => {
    const { status, body } = await get(ids.publicProcessed, stranger);
    expect(status).toBe(200);
    expect(activityDetailSchema.parse(body)).toEqual(body);
    expect(body).toEqual({
      id: ids.publicProcessed,
      title: "Sortie au lac",
      description: "Belle lumière",
      sportTypeCode: "run",
      startedAt: startedAt.toISOString(),
      endedAt: "2026-10-12T08:30:00.000Z",
      visibility: "public",
      processingStatus: "processed",
      locationName: "Annecy, Haute-Savoie",
      stats: {
        distanceM: 10234.5,
        movingTimeS: 3120,
        elapsedTimeS: 3300,
        elevationGainM: 245,
        avgSpeedMs: expect.closeTo(3.28, 5),
        maxSpeedMs: 5.5,
        avgHeartRate: 152,
        maxHeartRate: 181,
        calories: 812,
      },
      map: { polyline: "_p~iF~ps|U", precision: 5 },
      author: { id: author, displayName: "Camille Martin", avatarUrl: "https://cdn.test/a.png" },
      engagement: { kudosCount: 2, commentCount: 1, viewerHasKudoed: true },
      viewerIsAuthor: false,
      updatedAt: updatedAt.toISOString(),
    });
  });

  it.each([
    ["pending", () => ids.pending, undefined],
    ["processing", () => ids.processing, undefined],
    ["failed", () => ids.failed, "invalid_trace"],
  ])("gives the author their %s Activity, without official values or track", async (state, id, error) => {
    const { status, body } = await get(id(), author);
    expect(status).toBe(200);
    expect(activityDetailSchema.parse(body)).toEqual(body);
    expect(body).toMatchObject({ id: id(), processingStatus: state, stats: null, map: null, viewerIsAuthor: true });
    expect(body.processingError).toBe(error);
    expect(body.locationName).toBeUndefined();
  });

  it("gives the author their processed Activity, whatever its visibility", async () => {
    for (const id of [ids.publicProcessed, ids.privateProcessed]) {
      const { status, body } = await get(id, author);
      expect(status).toBe(200);
      expect(body).toMatchObject({ processingStatus: "processed", viewerIsAuthor: true });
      expect(body.stats?.distanceM).toBe(10234.5);
      expect(body.engagement.viewerHasKudoed).toBe(false);
    }
  });

  it("gives an accepted follower a followers Activity", async () => {
    const { status, body } = await get(ids.followersProcessed, follower);
    expect(status).toBe(200);
    expect(body).toMatchObject({ id: ids.followersProcessed, visibility: "followers", viewerIsAuthor: false });
  });

  it.each([
    ["a private Activity", () => ids.privateProcessed, () => follower],
    ["a followers Activity without follow", () => ids.followersProcessed, () => stranger],
    ["a followers Activity with a pending follow", () => ids.followersProcessed, () => pendingFollower],
    ["a pending Activity", () => ids.pending, () => follower],
    ["a processing Activity", () => ids.processing, () => stranger],
    ["a failed Activity", () => ids.failed, () => stranger],
    ["an unknown id", () => randomUUID(), () => stranger],
  ])("answers 404 activity_not_found for %s", async (_case, id, viewer) => {
    const { status, body } = await get(id(), viewer());
    expect(status).toBe(404);
    expect(body.error.code).toBe("activity_not_found");
  });
});
