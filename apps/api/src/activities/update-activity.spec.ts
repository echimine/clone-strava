import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitter2, EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ACTIVITY_UPDATED_EVENT,
  activityDetailSchema,
  type ActivityDetail,
  type ActivityUpdatedEvent,
} from "@repo/contracts";
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
 * `PATCH /v1/activities/:id` (ADR-033 §4) over real HTTP and Postgres (ADR-024 §2). Sessions
 * come from `x-test-user` through a fake `AuthService` (see `activity-detail.spec.ts`).
 */
describe("PATCH /v1/activities/:id (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const stranger = randomUUID();
  const users = [author, stranger];
  const startedAt = new Date("2026-10-12T07:30:00.000Z");
  const initialUpdatedAt = new Date("2026-10-13T18:00:00.000Z");

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function patch(id: string, user: string, body: unknown) {
    const response = await fetch(`${baseUrl}/v1/activities/${id}`, {
      method: "PATCH",
      headers: { "x-test-user": user, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return {
      status: response.status,
      body: (await response.json()) as ActivityDetail & { error: { code: string } },
    };
  }

  /** A processed `run` of the author, 10.2 km in 52 min, unless overridden. */
  async function insertActivity(
    options: { visibility?: string; status?: string; distanceM?: number; movingTimeS?: number } = {},
  ): Promise<string> {
    const id = randomUUID();
    await sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility, processing_status, updated_at)
       values ($1, $2, 'run', 'Sortie au lac', 'Belle lumière', $3, $4, $5, $6, $7)`,
      [id, author, startedAt, new Date(startedAt.getTime() + 3_600_000), options.visibility ?? "public",
        options.status ?? "processed", initialUpdatedAt],
    );
    if ((options.status ?? "processed") === "processed") {
      await sql(
        `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m)
         values ($1, $2, $3, 3300, 245)`,
        [id, options.distanceM ?? 10234.5, options.movingTimeS ?? 3120],
      );
      await sql(
        `insert into activities.activity_track (activity_id, map_polyline, location_name)
         values ($1, '_p~iF~ps|U', 'Annecy, Haute-Savoie')`,
        [id],
      );
    }
    return id;
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
  }, 30_000);

  afterAll(async () => {
    // Cascades to the users' activities.
    await sql('delete from "user" where id = any($1)', [users]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("changes the title and answers 200 with the full detail and a new updatedAt", async () => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, { title: "  Tour du lac  " });

    expect(status).toBe(200);
    expect(activityDetailSchema.parse(body)).toEqual(body);
    expect(body).toMatchObject({
      id,
      title: "Tour du lac",
      description: "Belle lumière",
      sportTypeCode: "run",
      visibility: "public",
      processingStatus: "processed",
      locationName: "Annecy, Haute-Savoie",
      map: { polyline: "_p~iF~ps|U", precision: 5 },
      author: { id: author, displayName: "Camille Martin" },
      viewerIsAuthor: true,
    });
    expect(body.stats?.distanceM).toBe(10234.5);
    expect(Date.parse(body.updatedAt)).toBeGreaterThan(initialUpdatedAt.getTime());
  });

  it.each([
    ["the description", { description: "Vent de face" }, { description: "Vent de face" }],
    ["the sport", { sportTypeCode: "walk" }, { sportTypeCode: "walk" }],
    ["the visibility", { visibility: "private" }, { visibility: "private" }],
  ])("changes %s alone, leaving the other fields as they were", async (_field, request, expected) => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, request);

    expect(status).toBe(200);
    expect(body).toMatchObject({
      title: "Sortie au lac",
      description: "Belle lumière",
      sportTypeCode: "run",
      visibility: "public",
      ...expected,
    });
    const reread = await fetch(`${baseUrl}/v1/activities/${id}`, { headers: { "x-test-user": author } });
    expect(await reread.json()).toEqual(body);
  });

  it("changes every field at once", async () => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, {
      title: "Balade",
      description: "Avec le chien",
      sportTypeCode: "hike",
      visibility: "followers",
    });

    expect(status).toBe(200);
    expect(body).toMatchObject({
      title: "Balade",
      description: "Avec le chien",
      sportTypeCode: "hike",
      visibility: "followers",
    });
  });

  it.each([
    ["null", null],
    ["empty", ""],
  ])("clears the description when it is %s", async (_case, description) => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, { description });

    expect(status).toBe(200);
    expect(body.description).toBeUndefined();
    const [row] = await sql("select description from activities.activity where id = $1", [id]);
    expect(row).toEqual({ description: null });
  });

  it("sets a new updatedAt on every PATCH, even one that changes nothing", async () => {
    const id = await insertActivity();

    const first = await patch(id, author, { title: "Tour du lac" });
    const second = await patch(id, author, { title: "Tour du lac" });

    expect(Date.parse(first.body.updatedAt)).toBeGreaterThan(initialUpdatedAt.getTime());
    expect(Date.parse(second.body.updatedAt)).toBeGreaterThan(Date.parse(first.body.updatedAt));
  });

  it("emits activities.activity.updated after the commit with the fields that changed", async () => {
    const id = await insertActivity();
    const events: ActivityUpdatedEvent[] = [];
    const listener = (event: ActivityUpdatedEvent) => events.push(event);
    const emitter = app.get(EventEmitter2);
    emitter.on(ACTIVITY_UPDATED_EVENT, listener);
    try {
      await patch(id, author, { title: "Tour du lac", visibility: "public", sportTypeCode: "walk" });
      await patch(id, author, { title: "Tour du lac" });
    } finally {
      emitter.off(ACTIVITY_UPDATED_EVENT, listener);
    }

    expect(events).toEqual([{ activityId: id, userId: author, changedFields: ["title", "sportTypeCode"] }]);
  });

  it("answers 404 activity_not_found for an Activity the athlete cannot see, or an unknown id", async () => {
    const privateId = await insertActivity({ visibility: "private" });

    for (const id of [privateId, randomUUID()]) {
      const { status, body } = await patch(id, stranger, { title: "Pirate" });
      expect(status).toBe(404);
      expect(body.error.code).toBe("activity_not_found");
    }
  });

  it("answers 403 not_activity_author to another athlete who sees the Activity, and changes nothing", async () => {
    const id = await insertActivity();

    const { status, body } = await patch(id, stranger, { title: "Pirate" });

    expect(status).toBe(403);
    expect(body.error.code).toBe("not_activity_author");
    const [row] = await sql("select title, updated_at from activities.activity where id = $1", [id]);
    expect(row).toEqual({ title: "Sortie au lac", updated_at: initialUpdatedAt });
  });

  it.each(["pending", "processing", "failed"])(
    "answers 409 activity_not_editable on a %s Activity",
    async (state) => {
      const id = await insertActivity({ status: state });

      const { status, body } = await patch(id, author, { title: "Tour du lac" });

      expect(status).toBe(409);
      expect(body.error.code).toBe("activity_not_editable");
    },
  );

  it.each([
    ["an empty body", {}],
    ["a blank title", { title: "   " }],
    ["a title over 255 characters", { title: "a".repeat(256) }],
    ["a description over 10,000 characters", { description: "a".repeat(10_001) }],
    ["an unknown visibility", { visibility: "friends" }],
  ])("answers 422 validation_error for %s", async (_case, request) => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, request);

    expect(status).toBe(422);
    expect(body.error.code).toBe("validation_error");
  });

  it("answers 422 validation_error on sportTypeCode for an unknown sport", async () => {
    const id = await insertActivity();

    const { status, body } = await patch(id, author, { sportTypeCode: "curling" });

    expect(status).toBe(422);
    expect(body.error).toMatchObject({ code: "validation_error", details: [{ field: "sportTypeCode" }] });
  });

  it.each([
    // hike: 300 s minimum.
    ["moving time under the new sport's minimum", { movingTimeS: 240, distanceM: 1500 }, "hike"],
    // ride: 200 m minimum, GPS sport.
    ["distance under the new GPS sport's minimum", { movingTimeS: 600, distanceM: 150 }, "ride"],
  ])("answers 422 activity_too_short_for_sport for a %s, and keeps the sport", async (_case, stats, sport) => {
    const id = await insertActivity(stats);

    const { status, body } = await patch(id, author, { sportTypeCode: sport, title: "Tour du lac" });

    expect(status).toBe(422);
    expect(body.error.code).toBe("activity_too_short_for_sport");
    const [row] = await sql("select sport_type_code, title from activities.activity where id = $1", [id]);
    expect(row).toEqual({ sport_type_code: "run", title: "Sortie au lac" });
  });

  it("does not hold the distance against a sport without GPS", async () => {
    // swim: no GPS, 50 m minimum; 30 m measured.
    const id = await insertActivity({ movingTimeS: 600, distanceM: 30 });

    const { status, body } = await patch(id, author, { sportTypeCode: "swim" });

    expect(status).toBe(200);
    expect(body.sportTypeCode).toBe("swim");
  });
});
