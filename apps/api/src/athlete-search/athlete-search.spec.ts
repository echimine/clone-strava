import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ViewerFilterModule } from "../viewer-filter/viewer-filter.module.js";
import type { AthleteSearchResponse } from "@repo/contracts";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SocialModule } from "@repo/core/social";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { AthleteSearchController } from "./athlete-search.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";

/**
 * `GET /v1/athletes/search?q=` (ADR-036 §2) over real HTTP and Postgres:
 * accent- and case-insensitive substring matching on profile names, word
 * starts first, the viewer excluded. Sessions come from `x-test-user`
 * through a fake `AuthService` (see `feed.spec.ts`).
 */
describe("athlete search (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  const users: string[] = [];
  /**
   * Unique per run, so other specs' athletes never crowd the 20 results;
   * letters only, starting with `q` so names that start with it sort last.
   */
  const tag = `q${randomUUID().slice(0, 7).replace(/\d/g, "q")}`;

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function search(viewer: string, q?: string) {
    const query = q === undefined ? "" : `?q=${encodeURIComponent(q)}`;
    return fetch(`${baseUrl}/v1/athletes/search${query}`, { headers: { "x-test-user": viewer } });
  }

  async function results(viewer: string, q: string) {
    const response = await search(viewer, q);
    expect(response.status).toBe(200);
    return (await response.json()) as AthleteSearchResponse;
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  /** A new athlete with profile names (`null`: no `user_profile` row). */
  async function athlete(names: { first: string | null; last: string | null } | null, accountName = "Compte") {
    const id = randomUUID();
    users.push(id);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, accountName, `${id}@test.local`]);
    if (names) {
      await sql("insert into users.user_profile (user_id, first_name, last_name) values ($1, $2, $3)", [
        id,
        names.first,
        names.last,
      ]);
    }
    return id;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        AnalyticsModule.forRoot({}),
        ViewerFilterModule,
        StorageModule.forRoot({
          endpoint: "https://bucket.test",
          region: "test",
          bucket: "test",
          accessKeyId: "test",
          secretAccessKey: "test",
        }),
        SocialModule,
        UsersModule,
      ],
      controllers: [AthleteSearchController],
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
  }, 30_000);

  afterAll(async () => {
    if (users.length > 0) {
      await sql('delete from "user" where id = any($1)', [users]);
    }
    await app?.close();
  });

  it("finds « Éliott Chimine » from « eli », « ÉLI » and « chim », with the viewer's follow status", async () => {
    const viewer = await athlete({ first: "Viewer", last: tag });
    const eliott = await athlete({ first: "Éliott", last: `Chimine${tag}` });

    for (const q of ["eli", "ÉLI", "chim"]) {
      const { items } = await results(viewer, q);
      expect(items).toContainEqual({
        athlete: { id: eliott, displayName: `Éliott Chimine${tag}`, avatarUrl: null },
        viewerFollowStatus: "none",
      });
    }
  });

  it("answers 422 invalid_query unless the trimmed query holds 2 to 50 characters", async () => {
    const viewer = await athlete({ first: "Viewer", last: tag });

    for (const q of [undefined, "", "e", "  é  ", "x".repeat(51)]) {
      const response = await search(viewer, q);
      expect(response.status).toBe(422);
      expect(await errorCode(response)).toBe("invalid_query");
    }
    expect((await search(viewer, `  ${"x".repeat(50)}  `)).status).toBe(200);
  });

  it("never returns the viewer, and accounts without profile names are not findable", async () => {
    const viewer = await athlete({ first: "Moi", last: `Même${tag}` });
    const namesake = await athlete({ first: "Toi", last: `Même${tag}` });
    await athlete(null, `Même${tag}`);
    await athlete({ first: null, last: null }, `Même${tag}`);

    const { items } = await results(viewer, `meme${tag}`);
    expect(items.map((item) => item.athlete.id)).toEqual([namesake]);
  });

  it("puts word-start matches first, then alphabetical order, at most 20", async () => {
    const viewer = await athlete({ first: "Viewer", last: tag });
    const word = `${tag}w`;
    const inside = await athlete({ first: "Aline", last: `Al${word}bert` });
    const lastName = await athlete({ first: "Bruno", last: `${word}Martin` });
    const firstName = await athlete({ first: `${word}anne`, last: "Durand" });
    const compound = await athlete({ first: "Claire", last: `Dupont-${word}` });

    const { items } = await results(viewer, word);
    expect(items.map((item) => item.athlete.id)).toEqual([lastName, compound, firstName, inside]);

    for (let index = 0; index < 20; index += 1) {
      await athlete({ first: "Nombreux", last: `${word}x${index}` });
    }
    expect((await results(viewer, `${word}x`)).items).toHaveLength(20);
  });

  it("matches %, _ and \\ literally", async () => {
    const viewer = await athlete({ first: "Viewer", last: tag });
    const percent = await athlete({ first: "Cent", last: `${tag}%off` });
    await athlete({ first: "Autre", last: `${tag}xoff` });

    expect((await results(viewer, "%off")).items.map((item) => item.athlete.id)).toEqual([percent]);
    expect((await results(viewer, `${tag}_off`)).items).toEqual([]);
    expect((await results(viewer, "\\%")).items).toEqual([]);
  });

  it("gives the viewer's follow status of each athlete", async () => {
    const viewer = await athlete({ first: "Viewer", last: tag });
    const followed = await athlete({ first: "Suivi", last: `Statut${tag}` });
    const requested = await athlete({ first: "Demandé", last: `Statut${tag}` });
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted'), ($1, $3, 'pending')", [
      viewer,
      followed,
      requested,
    ]);

    const { items } = await results(viewer, `statut${tag}`);
    expect(new Map(items.map((item) => [item.athlete.id, item.viewerFollowStatus]))).toEqual(
      new Map([
        [followed, "accepted"],
        [requested, "pending"],
      ]),
    );
  });
});
