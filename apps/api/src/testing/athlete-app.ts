import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { ThrottlerStorage } from "@nestjs/throttler";
import { AuthService } from "@repo/core/auth";
import { DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageService } from "@repo/core/storage";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { InMemoryStorage } from "./in-memory-storage.js";
import { listenOnLoopback } from "./listen-on-loopback.js";

/** The CI's dummy environment (`.github/workflows/deploy.yml`): `AppModule` reads it when loaded. */
const TEST_ENV = {
  NODE_ENV: "test",
  DATABASE_URL: TEST_DATABASE_URL,
  REDIS_URL: TEST_REDIS_URL,
  LOG_LEVEL: "error",
  BETTER_AUTH_SECRET: "test-secret-at-least-32-characters-long-0",
  BETTER_AUTH_URL: "http://127.0.0.1:0",
  REALTIME_TOKEN_SECRET: "test-realtime-secret",
  S3_ENDPOINT: "https://bucket.test",
  S3_REGION: "test",
  S3_BUCKET: "test",
  S3_ACCESS_KEY_ID: "test",
  S3_SECRET_ACCESS_KEY: "test",
  REVENUECAT_WEBHOOK_SECRET: "test",
  RESEND_API_KEY: "re_test_dummy_key_never_sent",
  RESEND_WEBHOOK_SECRET: "test",
  GOOGLE_CLIENT_ID: "test",
  GOOGLE_CLIENT_SECRET: "test",
};

export interface AthleteApp {
  app: INestApplication;
  /** Raw SQL on the test database. */
  sql: <Row = Record<string, unknown>>(text: string, params?: unknown[]) => Promise<Row[]>;
  /** Calls `/v1<path>` as the athlete `userId`. */
  call: (path: string, userId: string, init?: { method?: string; body?: unknown }) => Promise<Response>;
  /** A new athlete with a profile name, so search finds them. */
  seedAthlete: (firstName: string, options?: { lastName?: string; bio?: string; avatarKey?: string }) => Promise<string>;
  /** A processed Activity with stats and track (a feed item), `public` unless said otherwise. */
  seedActivity: (userId: string, options?: { visibility?: string; title?: string; description?: string }) => Promise<string>;
  /** Deletes the seeded athletes (cascades) and closes the app. */
  close: () => Promise<void>;
}

/**
 * The real `AppModule` over HTTP, Postgres and Redis (ADR-024 §2), for specs that cross many
 * routes of the athlete app (the viewer filter of ADR-038 §7 reaches a dozen read paths).
 * Sessions come from `x-test-user` through a fake `AuthService`; S3 is an `InMemoryStorage`; the
 * global 100/min rate limit is lifted, since one spec makes more calls than that.
 */
export async function bootstrapAthleteApp(): Promise<AthleteApp> {
  await ensureTestDatabaseMigrated();
  Object.assign(process.env, TEST_ENV);
  delete process.env.POSTHOG_API_KEY;
  const { AppModule } = await import("../app.module.js");
  const seeded: string[] = [];
  let database: Database | undefined;
  const sql = async <Row,>(text: string, params: unknown[] = []) =>
    (await database!.$client.query(text, params)).rows as Row[];

  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(AuthService)
    .useValue({
      getSession: async (headers: Headers) => {
        const userId = headers.get("x-test-user");
        return userId
          ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
          : null;
      },
      getPublicIdentities: (userIds: string[]) =>
        sql('select id as "userId", name from "user" where id = any($1)', [userIds]),
    })
    .overrideProvider(StorageService)
    .useValue(new InMemoryStorage())
    .overrideProvider(ThrottlerStorage)
    .useValue({
      increment: async () => ({ totalHits: 1, timeToExpire: 60, isBlocked: false, timeToBlockExpire: 0 }),
    })
    .compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix("v1");
  const baseUrl = await listenOnLoopback(app);
  database = app.get<Database>(DATABASE);

  return {
    app,
    sql,
    call: (path, userId, init = {}) =>
      fetch(`${baseUrl}/v1${path}`, {
        method: init.method ?? "GET",
        headers: {
          "x-test-user": userId,
          ...(init.body === undefined ? {} : { "content-type": "application/json" }),
        },
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
      }),
    seedAthlete: async (firstName, options = {}) => {
      const id = randomUUID();
      seeded.push(id);
      const lastName = options.lastName ?? "Testeur";
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [
        id,
        `${firstName} ${lastName}`,
        `${id}@test.local`,
      ]);
      await sql(
        "insert into users.user_profile (user_id, first_name, last_name, bio, avatar_key) values ($1, $2, $3, $4, $5)",
        [id, firstName, lastName, options.bio ?? null, options.avatarKey ?? null],
      );
      return id;
    },
    seedActivity: async (userId, options = {}) => {
      const id = randomUUID();
      const startedAt = new Date(Date.now() - 3_600_000 - Math.floor(Math.random() * 1_000_000));
      await sql(
        `insert into activities.activity (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility, processing_status)
         values ($1, $2, 'run', $3, $4, $5, $6, $7, 'processed')`,
        [id, userId, options.title ?? "Sortie", options.description ?? null, startedAt,
          new Date(startedAt.getTime() + 3_600_000), options.visibility ?? "public"],
      );
      await sql(
        `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m, avg_speed_ms)
         values ($1, 10000, 3000, 3100, 100, 3.3)`,
        [id],
      );
      await sql(
        "insert into activities.activity_track (activity_id, map_polyline, location_name, route_trimmed) values ($1, '_p~iF~ps|U', 'Annecy', false)",
        [id],
      );
      return id;
    },
    close: async () => {
      if (seeded.length > 0) {
        await sql('delete from "user" where id = any($1)', [seeded]);
      }
      await app.close();
    },
  };
}
