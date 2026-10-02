import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FeedResponse, KudosResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { KudosController } from "../activities/kudos.controller.js";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "./feed-assembler.js";
import { FeedController } from "./feed.controller.js";

/**
 * `GET /v1/feed` and `/v1/activities/:id/kudos` over real HTTP and Postgres
 * (ADR-024 §2 integration tier, ADR-029). Sessions come from `x-test-user`
 * through a fake `AuthService` (see `activity-imports.spec.ts`).
 */
describe("/v1/feed and kudos (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const viewer = randomUUID();
  const friend = randomUUID();
  const pendingFriend = randomUUID();
  const stranger = randomUUID();
  const users = [viewer, friend, pendingFriend, stranger];
  const ids = {
    mine: randomUUID(),
    mineProcessing: randomUUID(),
    friendPublic: randomUUID(),
    friendFollowers: randomUUID(),
    friendPrivate: randomUUID(),
    pendingFriendPublic: randomUUID(),
    strangerPublic: randomUUID(),
    strangerFollowers: randomUUID(),
  };

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, method = "GET") {
    return fetch(`${baseUrl}/v1${path}`, { method, headers: { "x-test-user": user } });
  }

  async function insertActivity(
    id: string,
    userId: string,
    hoursAgo: number,
    options: { visibility?: string; status?: string } = {},
  ) {
    const startedAt = new Date(Date.now() - hoursAgo * 3_600_000);
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', $3, $4, $5, $6, $7)`,
      [id, userId, `Activity ${id.slice(0, 4)}`, startedAt, new Date(startedAt.getTime() + 3_600_000),
        options.visibility ?? "public", options.status ?? "processed"],
    );
    await sql(
      `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m)
       values ($1, 10234.5, 3120, 3300, 245)`,
      [id],
    );
    await sql(
      `insert into activities.activity_track (activity_id, map_polyline, location_name) values ($1, '_p~iF~ps|U', 'Annecy, Haute-Savoie')`,
      [id],
    );
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
      controllers: [FeedController, KudosController],
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
    await sql("insert into users.user_profile (user_id, first_name, last_name, avatar_url) values ($1, 'Camille', 'Martin', 'https://cdn.test/a.png')", [friend]);
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted'), ($1, $3, 'pending')", [viewer, friend, pendingFriend]);

    await insertActivity(ids.mine, viewer, 1);
    await insertActivity(ids.mineProcessing, viewer, 0.5, { status: "processing" });
    await insertActivity(ids.friendPublic, friend, 2);
    await insertActivity(ids.friendFollowers, friend, 3, { visibility: "followers" });
    await insertActivity(ids.friendPrivate, friend, 4, { visibility: "private" });
    await insertActivity(ids.pendingFriendPublic, pendingFriend, 5);
    await insertActivity(ids.strangerPublic, stranger, 6);
    await insertActivity(ids.strangerFollowers, stranger, 7, { visibility: "followers" });
    await sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [friend, ids.mine]);
    await sql("insert into engagement.comment (user_id, activity_id, body) values ($1, $2, 'Bravo'), ($1, $2, 'Supprimé')", [friend, ids.mine]);
    await sql("update engagement.comment set deleted_at = now() where body = 'Supprimé' and activity_id = $1", [ids.mine]);
  }, 30_000);

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("lists own processed activities and accepted followees' visible ones, newest first", async () => {
    const response = await call("/feed", viewer);
    expect(response.status).toBe(200);
    const body = (await response.json()) as FeedResponse;
    expect(body.items.map((item) => item.id)).toEqual([ids.mine, ids.friendPublic, ids.friendFollowers]);
    expect(body.nextCursor).toBeNull();

    const [mine, friendPublic] = body.items;
    expect(mine).toMatchObject({
      locationName: "Annecy, Haute-Savoie",
      stats: { distanceM: 10234.5, movingTimeS: 3120, elevationGainM: 245 },
      map: { polyline: "_p~iF~ps|U", precision: 5 },
      author: { id: viewer, displayName: "User 0", avatarUrl: null },
      engagement: { kudosCount: 1, commentCount: 1, viewerHasKudoed: false },
      viewerIsAuthor: true,
    });
    expect(friendPublic?.author).toEqual({ id: friend, displayName: "Camille Martin", avatarUrl: "https://cdn.test/a.png" });
  });

  it("walks pages with a cursor without duplicates", async () => {
    const first = (await (await call("/feed?limit=2", viewer)).json()) as FeedResponse;
    expect(first.items).toHaveLength(2);
    expect(first.nextCursor).not.toBeNull();
    const second = (await (await call(`/feed?limit=2&cursor=${first.nextCursor}`, viewer)).json()) as FeedResponse;
    expect(second.items.map((item) => item.id)).toEqual([ids.friendFollowers]);
    expect(second.nextCursor).toBeNull();
  });

  it("rejects an invalid cursor with 422", async () => {
    const response = await call("/feed?cursor=garbage", viewer);
    expect(response.status).toBe(422);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("invalid_cursor");
  });

  it("gives and removes kudos idempotently", async () => {
    const give = async () => (await call(`/activities/${ids.friendPublic}/kudos`, viewer, "PUT")).json() as Promise<KudosResponse>;
    expect(await give()).toEqual({ activityId: ids.friendPublic, kudosCount: 1, viewerHasKudoed: true });
    expect((await give()).kudosCount).toBe(1);

    const feed = (await (await call("/feed", viewer)).json()) as FeedResponse;
    expect(feed.items.find((item) => item.id === ids.friendPublic)?.engagement.viewerHasKudoed).toBe(true);

    const removed = await call(`/activities/${ids.friendPublic}/kudos`, viewer, "DELETE");
    expect(await removed.json()).toEqual({ activityId: ids.friendPublic, kudosCount: 0, viewerHasKudoed: false });
  });

  it("refuses kudos on one's own activity and on invisible activities", async () => {
    const own = await call(`/activities/${ids.mine}/kudos`, viewer, "PUT");
    expect(own.status).toBe(422);
    expect(((await own.json()) as { error: { code: string } }).error.code).toBe("cannot_kudos_own_activity");

    expect((await call(`/activities/${ids.friendPrivate}/kudos`, viewer, "PUT")).status).toBe(404);
    expect((await call(`/activities/${ids.strangerFollowers}/kudos`, viewer, "PUT")).status).toBe(404);
    expect((await call(`/activities/${randomUUID()}/kudos`, viewer, "PUT")).status).toBe(404);
    expect((await call(`/activities/${ids.strangerPublic}/kudos`, viewer, "PUT")).status).toBe(200);
  });
});
