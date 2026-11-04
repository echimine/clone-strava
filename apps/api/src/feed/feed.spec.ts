import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { activityMediaPrefix, type FeedResponse, type KudosResponse } from "@repo/contracts";
import { ActivitiesModule, ActivitiesService } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { KudosAssembler } from "../activities/kudos-assembler.js";
import { KudosController } from "../activities/kudos.controller.js";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "./feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { FeedController } from "./feed.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { signedAvatarUrl, signedMediaUrl } from "../testing/signed-urls.js";

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
  const friendAvatarKey = `avatars/${friend}/${randomUUID()}.jpg`;
  const pendingFriend = randomUUID();
  const stranger = randomUUID();
  const kudoers = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
  const users = [viewer, friend, pendingFriend, stranger, ...kudoers];
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

  const media = { video: randomUUID(), photo: randomUUID() };

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
    options: { visibility?: string; status?: string; routeTrimmed?: boolean } = {},
  ) {
    const startedAt = new Date(Date.now() - hoursAgo * 3_600_000);
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', $3, $4, $5, $6, $7)`,
      [id, userId, `Activity ${id.slice(0, 4)}`, startedAt, new Date(startedAt.getTime() + 3_600_000),
        options.visibility ?? "public", options.status ?? "processed"],
    );
    await sql(
      `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m, avg_speed_ms)
       values ($1, 10234.5, 3120, 3300, 245, 3.25)`,
      [id],
    );
    await sql(
      `insert into activities.activity_track (activity_id, map_polyline, location_name, route_trimmed)
       values ($1, '_p~iF~ps|U', 'Annecy, Haute-Savoie', $2)`,
      [id, options.routeTrimmed ?? false],
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
        ViewerFilterModule,
        ActivitiesModule,
        EngagementModule,
        UsersModule,
      ],
      controllers: [FeedController, KudosController],
      providers: [
        SessionGuard,
        FeedAssembler,
        MediaAssembler,
        AthleteIdentities,
        KudosAssembler,
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
              sql('select id as "userId", name from "user" where id = any($1)', [userIds]),
          },
        },
        { provide: APP_PIPE, useClass: ZodValidationPipe },
        { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
        { provide: APP_FILTER, useClass: GlobalExceptionFilter },
      ],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);

    for (const [index, id] of users.entries()) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, `User ${index}`, `${id}@test.local`]);
    }
    // `user.image` (a Google photo) is never read: only `avatar_key` makes an `avatarUrl` (ADR-037 §2).
    await sql("with profile as (insert into users.user_profile (user_id, first_name, last_name, avatar_key) values ($1, 'Camille', 'Martin', $2)) update \"user\" set image = 'https://cdn.test/a.png' where id = $1", [friend, friendAvatarKey]);
    await sql("update \"user\" set image = 'https://cdn.test/viewer.png' where id = $1", [viewer]);
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted'), ($1, $3, 'pending')", [viewer, friend, pendingFriend]);

    await insertActivity(ids.mine, viewer, 1);
    await insertActivity(ids.mineProcessing, viewer, 0.5, { status: "processing" });
    await insertActivity(ids.friendPublic, friend, 2, { routeTrimmed: true });
    await insertActivity(ids.friendFollowers, friend, 3, { visibility: "followers" });
    await insertActivity(ids.friendPrivate, friend, 4, { visibility: "private" });
    await insertActivity(ids.pendingFriendPublic, pendingFriend, 5);
    await insertActivity(ids.strangerPublic, stranger, 6);
    await insertActivity(ids.strangerFollowers, stranger, 7, { visibility: "followers" });
    await sql("update activities.activity set media_first = true where id = $1", [ids.friendPublic]);
    await sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, duration_ms, position)
       values ($1, $3, $4, 'photo', 2048, 1536, null, 1), ($2, $3, $5, 'video', 1280, 720, 8000, 0)`,
      [media.photo, media.video, ids.friendPublic, `activities/${friend}/${ids.friendPublic}/media/${media.photo}/`,
        `activities/${friend}/${ids.friendPublic}/media/${media.video}/`],
    );
    await sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [friend, ids.mine]);
    await sql("insert into engagement.comment (user_id, activity_id, body) values ($1, $2, 'Bravo'), ($1, $2, 'Supprimé')", [friend, ids.mine]);
    await sql("update engagement.comment set deleted_at = now() where body = 'Supprimé' and activity_id = $1", [ids.mine]);
    // Kudoer i gave kudos i minutes ago: kudoers[0] is the most recent.
    for (const [index, kudoer] of kudoers.entries()) {
      await sql(
        "insert into engagement.kudos (user_id, activity_id, created_at) values ($1, $2, now() - make_interval(mins => $3))",
        [kudoer, ids.friendFollowers, index + 1],
      );
    }
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
      stats: { distanceM: 10234.5, movingTimeS: 3120, elevationGainM: 245, avgSpeedMs: 3.25 },
      map: { polyline: "_p~iF~ps|U", precision: 5 },
      routeTrimmed: false,
      author: { id: viewer, displayName: "User 0", avatarUrl: null },
      engagement: { kudosCount: 1, commentCount: 1, viewerHasKudoed: false },
      viewerIsAuthor: true,
    });
    expect(friendPublic?.routeTrimmed).toBe(true);
    expect(friendPublic?.author).toEqual({ id: friend, displayName: "Camille Martin", avatarUrl: signedAvatarUrl(friendAvatarKey) });
  });

  it("gives each card its signed Media in order and mediaFirst, with one Media read per page", async () => {
    const getMedia = vi.spyOn(app.get(ActivitiesService), "getMedia");
    const body = (await (await call("/feed", viewer)).json()) as FeedResponse;
    expect(getMedia).toHaveBeenCalledTimes(1);
    expect(getMedia).toHaveBeenCalledWith([ids.mine, ids.friendPublic, ids.friendFollowers]);
    getMedia.mockRestore();

    const byId = new Map(body.items.map((item) => [item.id, item]));
    const folder = (mediaId: string) => activityMediaPrefix(friend, ids.friendPublic, mediaId);
    expect(byId.get(ids.friendPublic)?.mediaFirst).toBe(true);
    expect(byId.get(ids.friendPublic)?.media).toEqual([
      {
        id: media.video,
        kind: "video",
        width: 1280,
        height: 720,
        durationMs: 8000,
        url: signedMediaUrl(folder(media.video), "original.mp4"),
        posterUrl: signedMediaUrl(folder(media.video), "poster.jpg"),
        thumbUrl: signedMediaUrl(folder(media.video), "thumb.jpg"),
      },
      {
        id: media.photo,
        kind: "photo",
        width: 2048,
        height: 1536,
        durationMs: null,
        url: signedMediaUrl(folder(media.photo), "original.jpg"),
        posterUrl: null,
        thumbUrl: signedMediaUrl(folder(media.photo), "thumb.jpg"),
      },
    ]);
    expect(byId.get(ids.mine)).toMatchObject({ media: [], mediaFirst: false });
  });

  it("gives each card its 3 most recent kudos givers, newest first", async () => {
    const body = (await (await call("/feed", viewer)).json()) as FeedResponse;
    const byId = new Map(body.items.map((item) => [item.id, item]));

    expect(byId.get(ids.friendFollowers)?.recentKudos).toEqual([
      { id: kudoers[0], displayName: "User 4", avatarUrl: null },
      { id: kudoers[1], displayName: "User 5", avatarUrl: null },
      { id: kudoers[2], displayName: "User 6", avatarUrl: null },
    ]);
    expect(byId.get(ids.friendFollowers)?.engagement.kudosCount).toBe(4);
    expect(byId.get(ids.mine)?.recentKudos).toEqual([
      { id: friend, displayName: "Camille Martin", avatarUrl: signedAvatarUrl(friendAvatarKey) },
    ]);
    expect(byId.get(ids.friendPublic)?.recentKudos).toEqual([]);
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
