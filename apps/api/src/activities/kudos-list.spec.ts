import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ListKudosResponse } from "@repo/contracts";
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
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { KudosController } from "./kudos.controller.js";

/**
 * `GET /v1/activities/:id/kudos` over real HTTP and Postgres (ADR-024 §2
 * integration tier, ADR-034 §1). Sessions come from `x-test-user` through
 * a fake `AuthService` (see `feed.spec.ts`).
 */
describe("GET /v1/activities/:id/kudos (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const author = randomUUID();
  const follower = randomUUID();
  const stranger = randomUUID();
  // Seven athletes giving kudos; two of them at the very same instant to exercise the `user_id` tie-break.
  const givers = Array.from({ length: 7 }, () => randomUUID());
  let publicActivity: string;
  let followersActivity: string;
  let privateActivity: string;

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string) {
    return fetch(`${baseUrl}/v1${path}`, { headers: { "x-test-user": user } });
  }

  async function list(activityId: string, user: string, query = "") {
    const response = await call(`/activities/${activityId}/kudos${query}`, user);
    expect(response.status).toBe(200);
    return (await response.json()) as ListKudosResponse;
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  async function insertActivity(visibility: string) {
    const id = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now() - interval '2 hours', now() - interval '1 hour', $3, 'processed')`,
      [id, author, visibility],
    );
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
      controllers: [KudosController],
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

    for (const [index, id] of [author, follower, stranger, ...givers].entries()) {
      await sql('insert into "user" (id, name, email, image) values ($1, $2, $3, $4)', [
        id,
        `User ${index}`,
        `${id}@test.local`,
        index === 3 ? "https://auth.test/u3.png" : null,
      ]);
    }
    // `user_profile` names and avatar win over Better Auth's (same rule as the feed).
    await sql(
      "insert into users.user_profile (user_id, first_name, last_name, avatar_url) values ($1, 'Camille', 'Martin', 'https://cdn.test/c.png')",
      [givers[1]],
    );
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [
      follower,
      author,
    ]);

    publicActivity = await insertActivity("public");
    followersActivity = await insertActivity("followers");
    privateActivity = await insertActivity("private");
    // givers[i] gave kudos i minutes ago, except givers[2] and givers[3] at the same microsecond.
    for (const [index, giver] of givers.entries()) {
      const minutesAgo = index === 3 ? 2 : index;
      await sql(
        `insert into engagement.kudos (user_id, activity_id, created_at)
         values ($1, $2, timestamptz '2026-10-16 10:00:00.123456+00' - make_interval(mins => $3))`,
        [giver, publicActivity, minutesAgo],
      );
    }
    await sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [givers[0], followersActivity]);
  });

  afterAll(async () => {
    await app?.close();
    await bullConnection?.quit();
  });

  /** The expected order: most recent first, ties broken by `user_id` descending. */
  function expectedOrder() {
    const tied = [givers[2]!, givers[3]!].sort().reverse();
    return [givers[0], givers[1], ...tied, givers[4], givers[5], givers[6]];
  }

  it("lists kudos most recent first, with athlete identities assembled as in the feed", async () => {
    const page = await list(publicActivity, stranger);

    expect(page.items.map((item) => item.athlete.id)).toEqual(expectedOrder());
    expect(page.nextCursor).toBeNull();
    expect(page.items[0]).toEqual({
      athlete: { id: givers[0], displayName: "User 3", avatarUrl: "https://auth.test/u3.png" },
      givenAt: "2026-10-16T10:00:00.123Z",
    });
    expect(page.items[1]?.athlete).toEqual({
      id: givers[1],
      displayName: "Camille Martin",
      avatarUrl: "https://cdn.test/c.png",
    });
  });

  it("pages with the opaque cursor without skipping or repeating athletes, even on equal timestamps", async () => {
    const seen: string[] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const query: string = `?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`;
      const page = await list(publicActivity, stranger, query);
      expect(page.items.length).toBeLessThanOrEqual(2);
      seen.push(...page.items.map((item) => item.athlete.id));
      cursor = page.nextCursor;
      pages += 1;
    } while (cursor && pages < 10);

    expect(pages).toBe(4);
    expect(seen).toEqual(expectedOrder());
  });

  it("defaults to 20 items and caps the limit at 50", async () => {
    expect((await call(`/activities/${publicActivity}/kudos?limit=51`, stranger)).status).toBe(422);
    expect((await call(`/activities/${publicActivity}/kudos?limit=0`, stranger)).status).toBe(422);
    expect((await list(publicActivity, stranger, "?limit=50")).items).toHaveLength(7);
  });

  it("answers an empty page on an Activity without kudos", async () => {
    expect(await list(privateActivity, author)).toEqual({ items: [], nextCursor: null });
  });

  it("follows the Activity's visibility: 404 activity_not_found when the viewer cannot see it", async () => {
    expect((await list(followersActivity, follower)).items.map((item) => item.athlete.id)).toEqual([givers[0]]);

    const hidden = await call(`/activities/${followersActivity}/kudos`, stranger);
    expect(hidden.status).toBe(404);
    expect(await errorCode(hidden)).toBe("activity_not_found");

    const privateOne = await call(`/activities/${privateActivity}/kudos`, follower);
    expect(privateOne.status).toBe(404);
    expect(await errorCode(privateOne)).toBe("activity_not_found");

    const unknown = await call(`/activities/${randomUUID()}/kudos`, author);
    expect(unknown.status).toBe(404);
    expect(await errorCode(unknown)).toBe("activity_not_found");
  });

  it("rejects a cursor it did not produce with 422 invalid_cursor", async () => {
    for (const cursor of ["nope", Buffer.from("2026-10-16|not-a-uuid").toString("base64url")]) {
      const response = await call(`/activities/${publicActivity}/kudos?cursor=${cursor}`, stranger);
      expect(response.status).toBe(422);
      expect(await errorCode(response)).toBe("invalid_cursor");
    }
  });

  it("needs a session", async () => {
    const response = await fetch(`${baseUrl}/v1/activities/${publicActivity}/kudos`);
    expect(response.status).toBe(401);
  });
});
