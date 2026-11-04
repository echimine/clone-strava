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
import type { AthleteStatsResponse, ProgressResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { GeocodingModule } from "@repo/core/geocoding";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { AthleteStatsController } from "./stats.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";

/**
 * `GET /v1/me/progress` and `GET /v1/athletes/:id/stats` (ADR-036 §4) over real HTTP and Postgres.
 * The clock is frozen on Wednesday 18 March 2026, 13:00 in Paris: the current week starts on
 * Monday 16 March, the 4 full weeks before it on 16 February.
 */
describe("Progress and statistics (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const athlete = randomUUID();
  const follower = randomUUID();
  const stranger = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string) {
    return fetch(`${baseUrl}/v1${path}`, { headers: { "x-test-user": user } });
  }

  async function insertActivity(options: {
    sport: string;
    startedAt: string;
    distanceM: number;
    movingTimeS: number;
    elevationGainM: number | null;
    visibility?: string;
    status?: string;
  }) {
    const id = randomUUID();
    const startedAt = new Date(options.startedAt);
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, $3, 'Sortie', $4, $5, $6, $7)`,
      [id, athlete, options.sport, startedAt, new Date(startedAt.getTime() + 3_600_000),
        options.visibility ?? "public", options.status ?? "processed"],
    );
    await sql(
      `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m)
       values ($1, $2, $3, $3, $4)`,
      [id, options.distanceM, options.movingTimeS, options.elevationGainM],
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
        ViewerFilterModule,
        StorageModule.forRoot({
          endpoint: "https://bucket.test",
          region: "test",
          bucket: "test",
          accessKeyId: "test",
          secretAccessKey: "test",
        }),
        GeocodingModule.forRoot({}),
        ActivitiesModule,
        UsersModule,
      ],
      controllers: [AthleteStatsController],
      providers: [
        SessionGuard,
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

    for (const [index, id] of [athlete, follower, stranger].entries()) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, `User ${index}`, `${id}@test.local`]);
    }
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [follower, athlete]);

    // Last year, 31 December 23:30 in Paris: all time only, but in the week of Monday 29 December.
    await insertActivity({ sport: "run", startedAt: "2025-12-31T22:30:00Z", distanceM: 20000, movingTimeS: 7200, elevationGainM: 300 });
    // 1 January 00:30 in Paris: this year. Elevation not computed.
    await insertActivity({ sport: "run", startedAt: "2025-12-31T23:30:00Z", distanceM: 7000, movingTimeS: 2100, elevationGainM: null });
    // Week of 16 February, private: only the athlete counts it.
    await insertActivity({ sport: "run", startedAt: "2026-02-18T07:00:00Z", distanceM: 6000, movingTimeS: 1800, elevationGainM: 30, visibility: "private" });
    // Week of 2 March, followers only.
    await insertActivity({ sport: "run", startedAt: "2026-03-02T07:00:00Z", distanceM: 8000, movingTimeS: 2400, elevationGainM: 50, visibility: "followers" });
    // Week of 9 March: a ride, and a run on Sunday 15 March 23:30 in Paris.
    await insertActivity({ sport: "ride", startedAt: "2026-03-10T07:00:00Z", distanceM: 40000, movingTimeS: 4800, elevationGainM: 400 });
    await insertActivity({ sport: "run", startedAt: "2026-03-15T22:30:00Z", distanceM: 10000, movingTimeS: 3000, elevationGainM: 100 });
    // Current week: a run, and one still processing (never counted).
    await insertActivity({ sport: "run", startedAt: "2026-03-16T07:00:00Z", distanceM: 5000, movingTimeS: 1500, elevationGainM: 20 });
    await insertActivity({ sport: "run", startedAt: "2026-03-17T07:00:00Z", distanceM: 9999, movingTimeS: 999, elevationGainM: 9, status: "processing" });

    vi.useFakeTimers({ toFake: ["Date"], now: new Date("2026-03-18T12:00:00Z") });
  });

  afterAll(async () => {
    vi.useRealTimers();
    await sql("delete from activities.activity where user_id = $1", [athlete]);
    await sql("delete from social.follow where followee_id = $1", [athlete]);
    await sql('delete from "user" where id = any($1)', [[athlete, follower, stranger]]);
    await app?.close();
    await bullConnection?.quit();
  });

  describe("GET /v1/me/progress", () => {
    it("returns the 12 Paris weeks of the sport, oldest first and zero-filled, with its Streak", async () => {
      const response = await call("/me/progress?sport=run", athlete);
      expect(response.status).toBe(200);
      const body = (await response.json()) as ProgressResponse;

      expect(body.sportTypeCode).toBe("run");
      expect(body.weeks).toHaveLength(12);
      expect(body.weeks[0]).toEqual({
        weekStart: "2025-12-29",
        distanceM: 27000,
        elevationGainM: 300,
        movingTimeS: 9300,
        activityCount: 2,
      });
      const active = body.weeks.filter((week) => week.activityCount > 0);
      expect(active.map((week) => week.weekStart)).toEqual(["2025-12-29", "2026-02-16", "2026-03-02", "2026-03-09", "2026-03-16"]);
      // The Sunday 23:30 Paris run counts for that Sunday's week, without the ride.
      expect(body.weeks[10]).toEqual({
        weekStart: "2026-03-09",
        distanceM: 10000,
        elevationGainM: 100,
        movingTimeS: 3000,
        activityCount: 1,
      });
      expect(body.weeks[11]?.weekStart).toBe("2026-03-16");
      expect(body.weeks[11]?.activityCount).toBe(1);
      expect(body.weeks[1]).toEqual({ weekStart: "2026-01-05", distanceM: 0, elevationGainM: 0, movingTimeS: 0, activityCount: 0 });

      expect(body.streak).toEqual({ weeks: 3, activeDays: ["2026-03-02", "2026-03-15", "2026-03-16"] });
    });

    it("rejects an unknown sport with 422", async () => {
      const response = await call("/me/progress?sport=curling", athlete);
      expect(response.status).toBe(422);
    });

    it("requires the sport", async () => {
      const response = await call("/me/progress", athlete);
      expect(response.status).toBe(422);
    });
  });

  describe("GET /v1/athletes/:id/stats", () => {
    it("gives the athlete all their processed Activities, all sports", async () => {
      const response = await call(`/athletes/${athlete}/stats`, athlete);
      expect(response.status).toBe(200);
      const body = (await response.json()) as AthleteStatsResponse;

      expect(body.sportTypeCode).toBeUndefined();
      // Weeks of 16 Feb to 9 March: the private run, the followers run, the ride and the Sunday run.
      expect(body.recent).toEqual({ weeks: 4, activitiesPerWeek: 1, movingTimeSPerWeek: 3000, distanceMPerWeek: 16000 });
      expect(body.yearToDate).toEqual({ activityCount: 6, movingTimeS: 15600, distanceM: 76000, elevationGainM: 600 });
      expect(body.allTime).toEqual({ activityCount: 7, distanceM: 96000, elevationGainM: 900 });
    });

    it("hides private and followers Activities from a stranger", async () => {
      const body = (await (await call(`/athletes/${athlete}/stats`, stranger)).json()) as AthleteStatsResponse;

      expect(body.recent).toEqual({ weeks: 4, activitiesPerWeek: 0.5, movingTimeSPerWeek: 1950, distanceMPerWeek: 12500 });
      expect(body.yearToDate).toEqual({ activityCount: 4, movingTimeS: 11400, distanceM: 62000, elevationGainM: 520 });
      expect(body.allTime).toEqual({ activityCount: 5, distanceM: 82000, elevationGainM: 820 });
    });

    it("shows followers Activities, never private ones, to an accepted follower", async () => {
      const body = (await (await call(`/athletes/${athlete}/stats`, follower)).json()) as AthleteStatsResponse;

      expect(body.recent).toEqual({ weeks: 4, activitiesPerWeek: 0.75, movingTimeSPerWeek: 2550, distanceMPerWeek: 14500 });
      expect(body.allTime.activityCount).toBe(6);
    });

    it("filters by sport", async () => {
      const response = await call(`/athletes/${athlete}/stats?sport=run`, stranger);
      expect(response.status).toBe(200);
      const body = (await response.json()) as AthleteStatsResponse;

      expect(body.sportTypeCode).toBe("run");
      expect(body.recent).toEqual({ weeks: 4, activitiesPerWeek: 0.25, movingTimeSPerWeek: 750, distanceMPerWeek: 2500 });
      expect(body.yearToDate).toEqual({ activityCount: 3, movingTimeS: 6600, distanceM: 22000, elevationGainM: 120 });
      expect(body.allTime).toEqual({ activityCount: 4, distanceM: 42000, elevationGainM: 420 });
    });

    it("rejects an unknown sport with 422", async () => {
      const response = await call(`/athletes/${athlete}/stats?sport=curling`, stranger);
      expect(response.status).toBe(422);
    });

    it("answers 404 athlete_not_found for an unknown athlete", async () => {
      const response = await call(`/athletes/${randomUUID()}/stats`, stranger);
      expect(response.status).toBe(404);
      expect(((await response.json()) as { error: { code: string } }).error.code).toBe("athlete_not_found");
    });
  });
});
