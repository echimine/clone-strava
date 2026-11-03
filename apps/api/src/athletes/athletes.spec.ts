import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { AthleteProfileResponse, FeedResponse, UpdateProfileResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { ItinerariesModule } from "@repo/core/itineraries";
import { SocialModule } from "@repo/core/social";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { FeedController } from "../feed/feed.controller.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { AthleteProfileAssembler } from "./athlete-profile-assembler.js";
import { AthletesController } from "./athletes.controller.js";
import { MeProfileController } from "./me-profile.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";

/**
 * `GET /v1/athletes/:id`, `GET /v1/athletes/:id/activities` and `PATCH /v1/me/profile`
 * (ADR-036 §3) over real HTTP and Postgres. Sessions come from `x-test-user` through a fake
 * `AuthService`. The clock is frozen on Wednesday 18 March 2026 in Paris: the current week starts
 * on Monday 16 March.
 */
describe("Athlete profile (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const athlete = randomUUID();
  const follower = randomUUID();
  const otherFollower = randomUUID();
  const latestFollower = randomUUID();
  const requester = randomUUID();
  const stranger = randomUUID();
  const renamed = randomUUID();
  const users = [athlete, follower, otherFollower, latestFollower, requester, stranger, renamed];
  const ids = {
    currentWeekRun: randomUUID(),
    followersRun: randomUUID(),
    privateSwim: randomUUID(),
    walk: randomUUID(),
    secondWalk: randomUUID(),
    hike: randomUUID(),
    processingRun: randomUUID(),
  };
  const hikePhoto = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: RequestInit = {}) {
    return fetch(`${baseUrl}/v1${path}`, {
      ...init,
      headers: { "x-test-user": user, "content-type": "application/json" },
    });
  }

  async function profile(athleteId: string, viewer: string): Promise<AthleteProfileResponse> {
    const response = await call(`/athletes/${athleteId}`, viewer);
    expect(response.status).toBe(200);
    return (await response.json()) as AthleteProfileResponse;
  }

  async function insertActivity(
    id: string,
    userId: string,
    sport: string,
    startedAt: string,
    options: { visibility?: string; status?: string } = {},
  ) {
    const start = new Date(startedAt);
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, $3, 'Sortie', $4, $5, $6, $7)`,
      [id, userId, sport, start, new Date(start.getTime() + 3_600_000),
        options.visibility ?? "public", options.status ?? "processed"],
    );
    await sql(
      `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m)
       values ($1, 10000, 3000, 3100, 50)`,
      [id],
    );
  }

  async function follow(followerId: string, followeeId: string, createdAt: string, status = "accepted") {
    await sql("insert into social.follow (follower_id, followee_id, status, created_at) values ($1, $2, $3, $4)", [
      followerId, followeeId, status, createdAt,
    ]);
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    bullConnection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        BullModule.forRoot({ connection: bullConnection, prefix: `test-${randomUUID()}` }),
        AnalyticsModule.forRoot({}),
        EventEmitterModule.forRoot({ wildcard: true, delimiter: "." }),
        StorageModule.forRoot({
          endpoint: "https://bucket.test",
          region: "test",
          bucket: "test",
          accessKeyId: "test",
          secretAccessKey: "test",
        }),
        GeocodingModule.forRoot({}),
        ElevationModule.forRoot({}),
        ActivitiesModule,
        EngagementModule,
        ItinerariesModule,
        SocialModule,
        UsersModule,
      ],
      controllers: [AthletesController, MeProfileController, FeedController],
      providers: [
        SessionGuard,
        AthleteIdentities,
        AthleteProfileAssembler,
        FeedAssembler,
        MediaAssembler,
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
            // Stands in for Better Auth's own write of `user.name`.
            setName: async (userId: string, name: string) => {
              await sql('update "user" set name = $2 where id = $1', [userId, name]);
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
    baseUrl = await listenOnLoopback(app);

    for (const [index, id] of users.entries()) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, `User ${index}`, `${id}@test.local`]);
    }
    await sql("insert into users.user_profile (user_id, first_name, last_name) values ($1, 'Léa', 'Martin')", [athlete]);
    await sql("insert into users.user_sport (user_id, sport_code, position) values ($1, 'ride', 0), ($1, 'run', 1)", [athlete]);

    await follow(follower, athlete, "2026-01-01T10:00:00Z");
    await follow(otherFollower, athlete, "2026-01-02T10:00:00Z");
    await follow(latestFollower, athlete, "2026-01-03T10:00:00Z");
    await follow(requester, athlete, "2026-01-04T10:00:00Z", "pending");
    await follow(athlete, follower, "2026-01-05T10:00:00Z");
    for (const followee of [follower, otherFollower, latestFollower]) {
      await follow(stranger, followee, "2026-01-06T10:00:00Z");
    }

    // Weeks of 16 March (current), 9 March, 2 March and 23 February.
    await insertActivity(ids.currentWeekRun, athlete, "run", "2026-03-16T07:00:00Z");
    await insertActivity(ids.followersRun, athlete, "run", "2026-03-10T07:00:00Z", { visibility: "followers" });
    await insertActivity(ids.privateSwim, athlete, "swim", "2026-03-03T07:00:00Z", { visibility: "private" });
    await insertActivity(ids.walk, athlete, "walk", "2026-02-24T07:00:00Z");
    await insertActivity(ids.secondWalk, athlete, "walk", "2026-02-25T07:00:00Z");
    await insertActivity(ids.hike, athlete, "hike", "2026-02-26T07:00:00Z");
    await insertActivity(ids.processingRun, athlete, "run", "2026-03-17T07:00:00Z", { status: "processing" });
    await sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height)
       values ($1, $2, $3, 'photo', 2048, 1536)`,
      [hikePhoto, ids.hike, `activities/${athlete}/${ids.hike}/media/${hikePhoto}/`],
    );

    for (const itinerary of [randomUUID(), randomUUID()]) {
      await sql(
        `insert into itineraries.itinerary (id, user_id, sport_type_code, name, distance_m, elevation_gain_m, elevation_source, track, map_polyline)
         values ($1, $2, 'run', 'Boucle', 5000, 40, 'ign', 'SRID=4326;LINESTRINGZ(6.1 45.9 450, 6.2 45.9 460)', '_p~iF~ps|U')`,
        [itinerary, athlete],
      );
    }

    vi.useFakeTimers({ toFake: ["Date"], now: new Date("2026-03-18T12:00:00Z") });
  });

  afterAll(async () => {
    vi.useRealTimers();
    await sql("delete from activities.activity where user_id = any($1)", [users]);
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
    await bullConnection?.quit();
  });

  describe("GET /v1/athletes/:id", () => {
    it("shows the athlete's own profile with every processed Activity and the own-profile fields", async () => {
      const body = await profile(athlete, athlete);
      expect(body).toEqual({
        athlete: { id: athlete, displayName: "Léa Martin", avatarUrl: null },
        activityCount: 6,
        streakWeeks: 4,
        followerCount: 3,
        followingCount: 1,
        viewerFollowStatus: null,
        followersYouKnow: [{ id: follower, displayName: "User 1", avatarUrl: null }],
        practicedSports: ["ride", "run", "walk", "hike", "swim"],
        approveFollowers: false,
        pendingFollowRequestCount: 1,
        itineraryCount: 2,
      });
    });

    it("hides private Activities from an accepted follower, who still sees followers-only ones", async () => {
      const body = await profile(athlete, follower);
      expect(body.activityCount).toBe(5);
      expect(body.streakWeeks).toBe(2);
      expect(body.viewerFollowStatus).toBe("accepted");
      expect(body.practicedSports).toEqual(["ride", "run", "walk", "hike"]);
      expect(body).not.toHaveProperty("approveFollowers");
      expect(body).not.toHaveProperty("pendingFollowRequestCount");
      expect(body).not.toHaveProperty("itineraryCount");
    });

    it("shows only public Activities to a stranger, with the athlete's followers they follow", async () => {
      const body = await profile(athlete, stranger);
      expect(body.activityCount).toBe(4);
      expect(body.streakWeeks).toBe(1);
      expect(body.viewerFollowStatus).toBe("none");
      expect(body.followersYouKnow.map((known) => known.id)).toEqual([latestFollower, otherFollower]);
    });

    it("shows a pending request as pending, with public Activities only", async () => {
      const body = await profile(athlete, requester);
      expect(body.viewerFollowStatus).toBe("pending");
      expect(body.activityCount).toBe(4);
    });

    it("is 404 athlete_not_found for an unknown athlete and 400 for a malformed id", async () => {
      const unknown = await call(`/athletes/${randomUUID()}`, stranger);
      expect(unknown.status).toBe(404);
      expect(await unknown.json()).toMatchObject({ error: { code: "athlete_not_found" } });
      expect((await call("/athletes/not-a-uuid", stranger)).status).toBe(400);
    });
  });

  describe("GET /v1/athletes/:id/activities", () => {
    async function activityIds(viewer: string, query = ""): Promise<string[]> {
      const response = await call(`/athletes/${athlete}/activities${query}`, viewer);
      expect(response.status).toBe(200);
      return ((await response.json()) as FeedResponse).items.map((item) => item.id);
    }

    it("lists the athlete's processed Activities as feed items, newest first", async () => {
      const response = await call(`/athletes/${athlete}/activities`, athlete);
      const body = (await response.json()) as FeedResponse;
      expect(body.items.map((item) => item.id)).toEqual([
        ids.currentWeekRun, ids.followersRun, ids.privateSwim, ids.hike, ids.secondWalk, ids.walk,
      ]);
      expect(body.items[0]).toMatchObject({
        sportTypeCode: "run",
        author: { id: athlete, displayName: "Léa Martin" },
        engagement: { kudosCount: 0, commentCount: 0, viewerHasKudoed: false },
        recentKudos: [],
        viewerIsAuthor: true,
        media: [],
        mediaFirst: false,
      });
      // ADR-037 §7: profile Activities are feed items, Media included.
      expect(body.items[3]?.media).toEqual([
        expect.objectContaining({
          id: hikePhoto,
          kind: "photo",
          url: expect.stringMatching(new RegExp(`/media/${hikePhoto}/original\\.jpg\\?.*X-Amz-Expires=3600`)),
        }),
      ]);
      expect(body.nextCursor).toBeNull();
    });

    it("shows followers-only Activities to accepted followers and public ones to everyone else", async () => {
      expect(await activityIds(follower)).toEqual([ids.currentWeekRun, ids.followersRun, ids.hike, ids.secondWalk, ids.walk]);
      expect(await activityIds(stranger)).toEqual([ids.currentWeekRun, ids.hike, ids.secondWalk, ids.walk]);
      expect(await activityIds(requester)).toEqual([ids.currentWeekRun, ids.hike, ids.secondWalk, ids.walk]);
    });

    it("pages with the feed's keyset cursor", async () => {
      const first = (await (await call(`/athletes/${athlete}/activities?limit=3`, stranger)).json()) as FeedResponse;
      expect(first.items.map((item) => item.id)).toEqual([ids.currentWeekRun, ids.hike, ids.secondWalk]);
      expect(first.nextCursor).not.toBeNull();
      expect(await activityIds(stranger, `?limit=3&cursor=${first.nextCursor}`)).toEqual([ids.walk]);
      expect((await call(`/athletes/${athlete}/activities?cursor=garbage`, stranger)).status).toBe(422);
    });

    it("is 404 athlete_not_found for an unknown athlete", async () => {
      expect((await call(`/athletes/${randomUUID()}/activities`, stranger)).status).toBe(404);
    });
  });

  describe("PATCH /v1/me/profile", () => {
    function patch(user: string, body: unknown) {
      return call("/me/profile", user, { method: "PATCH", body: JSON.stringify(body) });
    }

    it("sets the trimmed name everyone sees, in the feed and in the account", async () => {
      const activity = randomUUID();
      await insertActivity(activity, renamed, "run", "2026-03-17T07:00:00Z");

      const response = await patch(renamed, { firstName: "  Jean ", lastName: "Dupont  " });
      expect(response.status).toBe(200);
      expect((await response.json()) as UpdateProfileResponse).toEqual({
        athlete: { id: renamed, displayName: "Jean Dupont", avatarUrl: null },
      });

      const feed = (await (await call("/feed", renamed)).json()) as FeedResponse;
      expect(feed.items.find((item) => item.id === activity)?.author.displayName).toBe("Jean Dupont");
      expect(await sql('select name from "user" where id = $1', [renamed])).toEqual([{ name: "Jean Dupont" }]);

      await patch(renamed, { firstName: "Jeanne", lastName: "Dupont" });
      expect((await profile(renamed, stranger)).athlete.displayName).toBe("Jeanne Dupont");
    });

    it("rejects a blank or too long name with 422", async () => {
      expect((await patch(renamed, { firstName: "   ", lastName: "Dupont" })).status).toBe(422);
      expect((await patch(renamed, { firstName: "Jean", lastName: "x".repeat(51) })).status).toBe(422);
      expect((await patch(renamed, { firstName: "Jean" })).status).toBe(422);
    });
  });
});
