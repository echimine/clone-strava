import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { activityMediaPrefix, type GalleryResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { ElevationModule } from "@repo/core/elevation";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SocialModule } from "@repo/core/social";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { MediaAssembler } from "../media/media-assembler.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { signedMediaUrl } from "../testing/signed-urls.js";
import { AthleteGalleryController } from "./athlete-gallery.controller.js";

/**
 * `GET /v1/athletes/:id/media` (ADR-037 §9) over real HTTP and Postgres: the athlete's Media the
 * viewer may see, newest Activity first then the Media order. Sessions come from `x-test-user`
 * through a fake `AuthService`; the bucket signs offline.
 */
describe("Athlete Gallery (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const athlete = randomUUID();
  const follower = randomUUID();
  const stranger = randomUUID();
  const users = [athlete, follower, stranger];
  const activities = {
    newest: randomUUID(),
    followersOnly: randomUUID(),
    privateRide: randomUUID(),
    processing: randomUUID(),
    oldest: randomUUID(),
    strangers: randomUUID(),
  };
  const media = {
    newestPhoto: randomUUID(),
    newestVideo: randomUUID(),
    followersPhoto: randomUUID(),
    privatePhoto: randomUUID(),
    processingPhoto: randomUUID(),
    oldestFirst: randomUUID(),
    oldestSecond: randomUUID(),
    oldestThird: randomUUID(),
    strangersPhoto: randomUUID(),
  };
  /** The athlete's own Gallery, in its expected order. */
  const ownGallery = [
    media.newestPhoto,
    media.newestVideo,
    media.followersPhoto,
    media.privatePhoto,
    media.oldestFirst,
    media.oldestSecond,
    media.oldestThird,
  ];

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string) {
    return fetch(`${baseUrl}/v1${path}`, { headers: { "x-test-user": user } });
  }

  async function gallery(viewer: string, query = ""): Promise<GalleryResponse> {
    const response = await call(`/athletes/${athlete}/media${query}`, viewer);
    expect(response.status).toBe(200);
    return (await response.json()) as GalleryResponse;
  }

  async function insertActivity(
    id: string,
    userId: string,
    title: string,
    startedAt: string,
    options: { visibility?: string; status?: string } = {},
  ) {
    const start = new Date(startedAt);
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status, media_first)
       values ($1, $2, 'run', $3, $4, $5, $6, $7, true)`,
      [id, userId, title, start, new Date(start.getTime() + 3_600_000),
        options.visibility ?? "public", options.status ?? "processed"],
    );
  }

  async function insertMedia(
    id: string,
    activityId: string,
    userId: string,
    options: { kind?: "photo" | "video"; position?: number; createdAt?: string } = {},
  ) {
    const kind = options.kind ?? "photo";
    await sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, duration_ms, position, created_at)
       values ($1, $2, $3, $4, 1536, 2048, $5, $6, $7)`,
      [id, activityId, `activities/${userId}/${activityId}/media/${id}/`, kind, kind === "video" ? 10_000 : null,
        options.position ?? 0, options.createdAt ?? "2026-03-01T10:00:00.123456Z"],
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
        SocialModule,
        UsersModule,
      ],
      controllers: [AthleteGalleryController],
      providers: [
        SessionGuard,
        AthleteIdentities,
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
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [
      follower, athlete,
    ]);

    await insertActivity(activities.newest, athlete, "Sortie du lundi", "2026-03-16T07:00:00Z");
    await insertActivity(activities.followersOnly, athlete, "Fractionné", "2026-03-10T07:00:00Z", { visibility: "followers" });
    await insertActivity(activities.privateRide, athlete, "Vélo", "2026-03-03T07:00:00Z", { visibility: "private" });
    await insertActivity(activities.processing, athlete, "En cours", "2026-03-17T07:00:00Z", { status: "processing" });
    await insertActivity(activities.oldest, athlete, "Balade", "2026-02-24T07:00:00Z");
    await insertActivity(activities.strangers, stranger, "Ailleurs", "2026-03-15T07:00:00Z");

    // Inserted out of order: the Gallery follows `(position, created_at)`, not insertion.
    await insertMedia(media.newestVideo, activities.newest, athlete, { kind: "video", position: 1 });
    await insertMedia(media.newestPhoto, activities.newest, athlete, { position: 0 });
    await insertMedia(media.followersPhoto, activities.followersOnly, athlete);
    await insertMedia(media.privatePhoto, activities.privateRide, athlete);
    await insertMedia(media.processingPhoto, activities.processing, athlete);
    // Same position: `created_at` (to the microsecond) breaks the tie.
    await insertMedia(media.oldestThird, activities.oldest, athlete, { position: 1 });
    await insertMedia(media.oldestSecond, activities.oldest, athlete, { createdAt: "2026-03-01T10:00:00.123457Z" });
    await insertMedia(media.oldestFirst, activities.oldest, athlete, { createdAt: "2026-03-01T10:00:00.123456Z" });
    await insertMedia(media.strangersPhoto, activities.strangers, stranger);
  });

  afterAll(async () => {
    await sql("delete from activities.activity where user_id = any($1)", [users]);
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("gives the owner every Media of their processed Activities, newest Activity first, then the Media order", async () => {
    const body = await gallery(athlete);
    expect(body.items.map((item) => item.id)).toEqual(ownGallery);
    expect(body.nextCursor).toBeNull();
    expect(body.items[0]).toEqual({
      id: media.newestPhoto,
      kind: "photo",
      width: 1536,
      height: 2048,
      durationMs: null,
      url: signedMediaUrl(activityMediaPrefix(athlete, activities.newest, media.newestPhoto), "original.jpg"),
      posterUrl: null,
      thumbUrl: signedMediaUrl(activityMediaPrefix(athlete, activities.newest, media.newestPhoto), "thumb.jpg"),
      activity: { id: activities.newest, title: "Sortie du lundi", startedAt: "2026-03-16T07:00:00.000Z" },
    });
    expect(body.items[1]).toMatchObject({
      kind: "video",
      durationMs: 10_000,
      posterUrl: signedMediaUrl(activityMediaPrefix(athlete, activities.newest, media.newestVideo), "poster.jpg"),
    });
  });

  it("shows an accepted follower followers-only Media but nothing private, and a stranger public Media only", async () => {
    expect((await gallery(follower)).items.map((item) => item.id)).toEqual([
      media.newestPhoto, media.newestVideo, media.followersPhoto, media.oldestFirst, media.oldestSecond, media.oldestThird,
    ]);
    expect((await gallery(stranger)).items.map((item) => item.id)).toEqual([
      media.newestPhoto, media.newestVideo, media.oldestFirst, media.oldestSecond, media.oldestThird,
    ]);
  });

  // Limit 1 puts a page boundary between every pair, the microsecond tie included.
  it.each([
    [1, 7],
    [2, 4],
  ])("pages by keyset without skipping or repeating a Media (limit %i)", async (limit, expectedPages) => {
    const seen: string[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const body: GalleryResponse = await gallery(athlete, `?limit=${limit}${cursor ? `&cursor=${cursor}` : ""}`);
      expect(body.items.length).toBeLessThanOrEqual(limit);
      seen.push(...body.items.map((item) => item.id));
      cursor = body.nextCursor;
      pages += 1;
    } while (cursor !== null && pages < 10);
    expect(seen).toEqual(ownGallery);
    expect(pages).toBe(expectedPages);
  });

  it("is 422 invalid_cursor for a cursor it did not produce, and 422 above 60 per page", async () => {
    const garbage = await call(`/athletes/${athlete}/media?cursor=garbage`, athlete);
    expect(garbage.status).toBe(422);
    expect(await garbage.json()).toMatchObject({ error: { code: "invalid_cursor" } });
    const feedCursor = Buffer.from(`2026-03-16T07:00:00.000Z|${activities.newest}`).toString("base64url");
    expect((await call(`/athletes/${athlete}/media?cursor=${feedCursor}`, athlete)).status).toBe(422);
    expect((await call(`/athletes/${athlete}/media?limit=61`, athlete)).status).toBe(422);
  });

  it("is 404 athlete_not_found for an unknown athlete", async () => {
    const response = await call(`/athletes/${randomUUID()}/media`, stranger);
    expect(response.status).toBe(404);
    expect(await response.json()).toMatchObject({ error: { code: "athlete_not_found" } });
  });
});
