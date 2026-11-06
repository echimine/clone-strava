import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import { activityDetailSchema, type ActivityDetail } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { SegmentsModule } from "@repo/core/segments";
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
import { MediaAssembler } from "../media/media-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { ActivitiesController } from "./activities.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { signedAvatarUrl, signedMediaUrl } from "../testing/signed-urls.js";

/** A stored Activity analysis (ADR-036 §6), as the worker writes it. */
const ANALYSIS = {
  splits: [
    { distanceM: 1000, movingTimeS: 305, elevationDiffM: 12.5, avgHeartRate: 148 },
    { distanceM: 234.5, movingTimeS: 70, elevationDiffM: -3, avgHeartRate: 155 },
  ],
  series: {
    distanceM: [0, 617.3, 1234.5],
    speedMs: [3.2, 3.4, 0],
    altitudeM: [450, 462.5, 459.5],
    heartRateBpm: [140, 150, 156],
  },
};

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
    importedWithoutFile: randomUUID(),
  };
  const media = { first: randomUUID(), video: randomUUID(), late: randomUUID(), ofPending: randomUUID() };
  const mediaFolder = (activityId: string, mediaId: string) => `activities/${author}/${activityId}/media/${mediaId}/`;
  const signed = (activityId: string, mediaId: string, file: string) =>
    signedMediaUrl(mediaFolder(activityId, mediaId), file);
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
    options: {
      visibility?: string;
      status?: string;
      error?: string;
      withResults?: boolean;
      source?: string;
      routeTrimmed?: boolean;
    } = {},
  ) {
    await sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility, processing_status, processing_error, updated_at, source)
       values ($1, $2, 'run', 'Sortie au lac', 'Belle lumière', $3, $4, $5, $6, $7, $8, $9)`,
      [id, author, startedAt, new Date(startedAt.getTime() + 3_600_000), options.visibility ?? "public",
        options.status ?? "processed", options.error ?? null, updatedAt, options.source ?? "recorded"],
    );
    if (options.withResults ?? true) {
      await sql(
        `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m,
           avg_speed_ms, max_speed_ms, avg_heart_rate, max_heart_rate, calories)
         values ($1, 10234.5, 3120, 3300, 245, 3.28, 5.5, 152, 181, 812)`,
        [id],
      );
      await sql(
        `insert into activities.activity_track (activity_id, map_polyline, location_name, route_trimmed)
         values ($1, '_p~iF~ps|U', 'Annecy, Haute-Savoie', $2)`,
        [id, options.routeTrimmed ?? false],
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
        ViewerFilterModule,
        ActivitiesModule,
        SegmentsModule,
        EngagementModule,
        UsersModule,
      ],
      controllers: [ActivitiesController],
      providers: [
        SessionGuard,
        FeedAssembler,
        MediaAssembler,
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
    await sql(
      "with profile as (insert into users.user_profile (user_id, first_name, last_name, avatar_key) values ($1, 'Camille', 'Martin', $2)) update \"user\" set image = 'https://cdn.test/a.png' where id = $1",
      [author, `avatars/${author}/a.jpg`],
    );
    await sql(
      "insert into social.follow (follower_id, followee_id, status) values ($1, $3, 'accepted'), ($2, $3, 'pending')",
      [follower, pendingFollower, author],
    );

    await insertActivity(ids.publicProcessed, { source: "imported", routeTrimmed: true });
    await sql(
      `insert into activities.activity_import (id, user_id, format, original_file_name, size_bytes, status, activity_id)
       values ($1, $2, 'fit', 'lac.fit', 1024, 'imported', $3)`,
      [randomUUID(), author, ids.publicProcessed],
    );
    await insertActivity(ids.importedWithoutFile, { source: "imported" });
    await insertActivity(ids.followersProcessed, { visibility: "followers", source: "manual" });
    await sql(
      "insert into activities.activity_analysis (activity_id, version, splits, series) values ($1, 1, $2, $3), ($4, 1, '[]', null)",
      [ids.publicProcessed, JSON.stringify(ANALYSIS.splits), JSON.stringify(ANALYSIS.series), ids.followersProcessed],
    );
    await insertActivity(ids.privateProcessed, { visibility: "private" });
    await insertActivity(ids.pending, { status: "pending", withResults: false });
    await insertActivity(ids.processing, { status: "processing", withResults: false });
    await insertActivity(ids.failed, { status: "failed", error: "invalid_trace", withResults: false });
    await sql("update activities.activity set media_first = true where id = $1", [ids.publicProcessed]);
    // Inserted out of order: the read order is (position, created_at) (ADR-037 §8).
    await sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, duration_ms, position, created_at)
       values ($1, $4, $5, 'photo', 1536, 2048, null, 1, '2026-10-12T10:00:02Z'),
              ($2, $4, $6, 'video', 1280, 720, 10500, 1, '2026-10-12T10:00:01Z'),
              ($3, $4, $7, 'photo', 2048, 1536, null, 0, '2026-10-12T10:00:03Z'),
              ($8, $9, $10, 'photo', 2048, 1536, null, 0, '2026-10-12T10:00:00Z')`,
      [media.late, media.video, media.first, ids.publicProcessed, mediaFolder(ids.publicProcessed, media.late),
        mediaFolder(ids.publicProcessed, media.video), mediaFolder(ids.publicProcessed, media.first),
        media.ofPending, ids.pending, mediaFolder(ids.pending, media.ofPending)],
    );
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

  it("gives another athlete a public processed Activity in full: author, map, place, stats, engagement, source", async () => {
    const { status, body } = await get(ids.publicProcessed, stranger);
    expect(status).toBe(200);
    expect(activityDetailSchema.parse(body)).toEqual(body);
    expect(body).toEqual({
      id: ids.publicProcessed,
      title: "Sortie au lac",
      description: "Belle lumière",
      source: "imported",
      importFormat: "fit",
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
      routeTrimmed: true,
      analysis: ANALYSIS,
      author: { id: author, displayName: "Camille Martin", avatarUrl: signedAvatarUrl(`avatars/${author}/a.jpg`) },
      engagement: { kudosCount: 2, commentCount: 1, viewerHasKudoed: true },
      viewerIsAuthor: false,
      media: expect.any(Array),
      mediaFirst: true,
      medalCounts: { gold: 0, silver: 0, bronze: 0 },
      updatedAt: updatedAt.toISOString(),
    });
  });

  it("gives the Media of an Activity in order, each file behind a 1-hour signed URL, and mediaFirst", async () => {
    const { status, body } = await get(ids.publicProcessed, stranger);
    expect(status).toBe(200);
    expect(body.mediaFirst).toBe(true);
    expect(body.media).toEqual([
      {
        id: media.first,
        kind: "photo",
        width: 2048,
        height: 1536,
        durationMs: null,
        url: signed(ids.publicProcessed, media.first, "original.jpg"),
        posterUrl: null,
        thumbUrl: signed(ids.publicProcessed, media.first, "thumb.jpg"),
      },
      {
        id: media.video,
        kind: "video",
        width: 1280,
        height: 720,
        durationMs: 10500,
        url: signed(ids.publicProcessed, media.video, "original.mp4"),
        posterUrl: signed(ids.publicProcessed, media.video, "poster.jpg"),
        thumbUrl: signed(ids.publicProcessed, media.video, "thumb.jpg"),
      },
      {
        id: media.late,
        kind: "photo",
        width: 1536,
        height: 2048,
        durationMs: null,
        url: signed(ids.publicProcessed, media.late, "original.jpg"),
        posterUrl: null,
        thumbUrl: signed(ids.publicProcessed, media.late, "thumb.jpg"),
      },
    ]);
  });

  it("gives an Activity without Media an empty list, media not first", async () => {
    const { body } = await get(ids.followersProcessed, follower);
    expect(body.media).toEqual([]);
    expect(body.mediaFirst).toBe(false);
  });

  it("gives the author the Media of an Activity not processed yet", async () => {
    const { body } = await get(ids.pending, author);
    expect(body.media).toEqual([expect.objectContaining({ id: media.ofPending, kind: "photo" })]);
  });

  it.each([
    ["pending", () => ids.pending, undefined],
    ["processing", () => ids.processing, undefined],
    ["failed", () => ids.failed, "invalid_trace"],
  ])("gives the author their %s Activity, without official values or track", async (state, id, error) => {
    const { status, body } = await get(id(), author);
    expect(status).toBe(200);
    expect(activityDetailSchema.parse(body)).toEqual(body);
    expect(body).toMatchObject({
      id: id(),
      processingStatus: state,
      source: "recorded",
      stats: null,
      map: null,
      routeTrimmed: false,
      analysis: null,
      viewerIsAuthor: true,
    });
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

  it("gives no import format to an imported Activity whose import is unknown, nor to a manual one", async () => {
    const imported = await get(ids.importedWithoutFile, stranger);
    expect(imported.status).toBe(200);
    expect(imported.body.source).toBe("imported");
    expect(imported.body.importFormat).toBeUndefined();
    const manual = await get(ids.followersProcessed, follower);
    expect(manual.body.importFormat).toBeUndefined();
  });

  it("gives an accepted follower a followers Activity", async () => {
    const { status, body } = await get(ids.followersProcessed, follower);
    expect(status).toBe(200);
    expect(body).toMatchObject({
      id: ids.followersProcessed,
      visibility: "followers",
      source: "manual",
      routeTrimmed: false,
      // ADR-036 §6: no trace, an empty analysis.
      analysis: { splits: [], series: null },
      viewerIsAuthor: false,
    });
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
