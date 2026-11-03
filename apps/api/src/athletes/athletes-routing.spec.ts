import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuthService } from "@repo/core/auth";
import { DATABASE, type Database } from "@repo/core/infrastructure";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";

/**
 * Route order of the real `AppModule`: Express matches routes in registration order, so the
 * static `GET /v1/athletes/search` (ADR-036 §2) must be registered before `GET /v1/athletes/:id`
 * (ADR-036 §3), whose UUID pipe would otherwise answer 400. Boots the whole app on the test
 * database; sessions come from `x-test-user` through a fake `AuthService`.
 */
describe("athletes routes in AppModule (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  const viewer = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string) {
    return fetch(`${baseUrl}/v1${path}`, { headers: { "x-test-user": viewer } });
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    // `AppModule` reads its environment when it is loaded: never the developer's own `.env`.
    Object.assign(process.env, {
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
    });
    delete process.env.POSTHOG_API_KEY;
    const { AppModule } = await import("../app.module.js");

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(AuthService)
      .useValue({
        getSession: async (headers: Headers) => {
          const userId = headers.get("x-test-user");
          return userId
            ? { userId, email: `${userId}@test.local`, name: "Test", role: "user", twoFactorEnabled: false }
            : null;
        },
        getPublicIdentities: async (userIds: string[]) =>
          sql('select id as "userId", name from "user" where id = any($1)', [userIds]),
      })
      .compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [viewer, "Viewer", `${viewer}@test.local`]);
  });

  afterAll(async () => {
    await sql('delete from "user" where id = $1', [viewer]);
    await app?.close();
  });

  it("answers GET /v1/athletes/search with the search, not as an athlete id", async () => {
    const response = await call("/athletes/search?q=xx");
    expect(response.status).toBe(200);
    expect(await response.json()).toHaveProperty("items");
  });

  it("still routes a UUID to the athlete profile", async () => {
    expect((await call(`/athletes/${viewer}`)).status).toBe(200);
    expect((await call(`/athletes/${randomUUID()}`)).status).toBe(404);
  });
});
