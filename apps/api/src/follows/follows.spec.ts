import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FeedResponse, FollowListResponse, FollowRequestListResponse, FollowResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SocialModule } from "@repo/core/social";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { FeedAssembler } from "../feed/feed-assembler.js";
import { FeedController } from "../feed/feed.controller.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { AthleteFollowsController } from "./athlete-follows.controller.js";
import { FollowListAssembler } from "./follow-list-assembler.js";
import { MeFollowsController } from "./me-follows.controller.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";

/**
 * Follows over real HTTP and Postgres (ADR-024 §2 integration tier,
 * ADR-036 §1): follow, unfollow, requests, lists, "Approuver mes abonnés",
 * and their effect on `GET /v1/feed`. Sessions come from `x-test-user`
 * through a fake `AuthService` (see `feed.spec.ts`).
 */
describe("follows (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  const users: string[] = [];

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, method = "GET", body?: unknown) {
    return fetch(`${baseUrl}/v1${path}`, {
      method,
      headers: { "x-test-user": user, ...(body === undefined ? {} : { "content-type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  async function json<T>(response: Response, status = 200): Promise<T> {
    expect(response.status).toBe(status);
    return (await response.json()) as T;
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  /** A new athlete, named `name` through Better Auth's `user.name`. */
  async function athlete(name = "Athlète") {
    const id = randomUUID();
    users.push(id);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, name, `${id}@test.local`]);
    return id;
  }

  const follow = (viewer: string, athleteId: string) => call(`/athletes/${athleteId}/follow`, viewer, "PUT");

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
        SocialModule,
        UsersModule,
      ],
      controllers: [AthleteFollowsController, MeFollowsController, FeedController],
      providers: [
        SessionGuard,
        AthleteIdentities,
        FollowListAssembler,
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
    await bullConnection?.quit();
  });

  it("follows an athlete who does not approve followers: accepted at once, and a second PUT changes nothing", async () => {
    const viewer = await athlete();
    const target = await athlete();

    expect(await json<FollowResponse>(await follow(viewer, target))).toEqual({
      athleteId: target,
      viewerFollowStatus: "accepted",
      followerCount: 1,
    });
    expect(await json<FollowResponse>(await follow(viewer, target))).toEqual({
      athleteId: target,
      viewerFollowStatus: "accepted",
      followerCount: 1,
    });
  });

  it("answers 422 cannot_follow_self and 404 athlete_not_found", async () => {
    const viewer = await athlete();

    const self = await follow(viewer, viewer);
    expect(self.status).toBe(422);
    expect(await errorCode(self)).toBe("cannot_follow_self");

    for (const method of ["PUT", "DELETE"]) {
      const unknown = await call(`/athletes/${randomUUID()}/follow`, viewer, method);
      expect(unknown.status).toBe(404);
      expect(await errorCode(unknown)).toBe("athlete_not_found");
    }
    for (const list of ["followers", "following"]) {
      const unknown = await call(`/athletes/${randomUUID()}/${list}`, viewer);
      expect(unknown.status).toBe(404);
      expect(await errorCode(unknown)).toBe("athlete_not_found");
    }
  });

  it("sends a pending request to an athlete who approves followers; accepting it opens their followers Activities in the feed", async () => {
    const viewer = await athlete();
    const target = await athlete();
    expect(await json(await call("/me/follow-settings", target, "PUT", { approveFollowers: true }))).toEqual({
      approveFollowers: true,
    });
    const activityId = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now() - interval '2 hours', now() - interval '1 hour', 'followers', 'processed')`,
      [activityId, target],
    );
    const feedIds = async () => (await json<FeedResponse>(await call("/feed", viewer))).items.map((item) => item.id);

    expect(await json<FollowResponse>(await follow(viewer, target))).toEqual({
      athleteId: target,
      viewerFollowStatus: "pending",
      followerCount: 0,
    });
    expect((await json<FollowResponse>(await follow(viewer, target))).viewerFollowStatus).toBe("pending");
    expect(await feedIds()).toEqual([]);

    const accepted = await call(`/me/follow-requests/${viewer}`, target, "PUT");
    expect(accepted.status).toBe(204);
    expect(await feedIds()).toEqual([activityId]);
    expect((await json<FollowResponse>(await follow(viewer, target))).followerCount).toBe(1);

    const again = await call(`/me/follow-requests/${viewer}`, target, "PUT");
    expect(again.status).toBe(404);
    expect(await errorCode(again)).toBe("follow_request_not_found");
  });

  it("turning approval off accepts every pending request; turning it on only affects new follows", async () => {
    const target = await athlete();
    const early = await athlete();
    const [first, second] = [await athlete(), await athlete()];
    await follow(early, target);
    await call("/me/follow-settings", target, "PUT", { approveFollowers: true });
    expect((await json<FollowResponse>(await follow(first, target))).viewerFollowStatus).toBe("pending");
    expect((await json<FollowResponse>(await follow(second, target))).viewerFollowStatus).toBe("pending");

    expect(await json(await call("/me/follow-settings", target, "PUT", { approveFollowers: false }))).toEqual({
      approveFollowers: false,
    });

    const followers = await json<FollowListResponse>(await call(`/athletes/${target}/followers`, target));
    expect(followers.items.map((item) => item.athlete.id).sort()).toEqual([early, first, second].sort());
    expect((await json<FollowRequestListResponse>(await call("/me/follow-requests", target))).items).toEqual([]);
  });

  it("lists followers and following most recent first by opaque cursor, each with the viewer's relation", async () => {
    const star = await athlete("Étoile");
    const fans = [await athlete("Fan 0"), await athlete("Fan 1"), await athlete("Fan 2"), await athlete("Fan 3")];
    const viewer = await athlete("Lecteur");
    // fans[i] followed the star i minutes ago; fans[1] and fans[2] at the very same instant (tie broken by id).
    for (const [index, fan] of fans.entries()) {
      await sql(
        `insert into social.follow (follower_id, followee_id, status, created_at)
         values ($1, $2, 'accepted', timestamptz '2026-11-03 10:00:00.123456+00' - make_interval(mins => $3))`,
        [fan, star, index === 2 ? 1 : index],
      );
    }
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'pending')", [
      await athlete(),
      star,
    ]);
    await follow(viewer, fans[0]!);
    await sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'pending')", [
      viewer,
      fans[3],
    ]);
    const tied = [fans[1]!, fans[2]!].sort().reverse();
    const expectedOrder = [fans[0], ...tied, fans[3]];

    const seen: FollowListResponse["items"] = [];
    let cursor: string | null = null;
    let pages = 0;
    do {
      const query: string = `?limit=3${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`;
      const page = await json<FollowListResponse>(await call(`/athletes/${star}/followers${query}`, viewer));
      seen.push(...page.items);
      cursor = page.nextCursor;
      pages += 1;
    } while (cursor && pages < 5);

    expect(pages).toBe(2);
    expect(seen.map((item) => item.athlete.id)).toEqual(expectedOrder);
    expect(seen[0]).toEqual({
      athlete: { id: fans[0], displayName: "Fan 0", avatarUrl: null },
      viewerFollowStatus: "accepted",
    });
    expect(seen.find((item) => item.athlete.id === fans[3])?.viewerFollowStatus).toBe("pending");
    expect(seen.find((item) => item.athlete.id === fans[1])?.viewerFollowStatus).toBe("none");

    // The viewer appears in fans[0]'s followers as themself (`null`).
    const ofFan = await json<FollowListResponse>(await call(`/athletes/${fans[0]}/followers`, viewer));
    expect(ofFan.items).toEqual([
      { athlete: { id: viewer, displayName: "Lecteur", avatarUrl: null }, viewerFollowStatus: null },
    ]);
    const following = await json<FollowListResponse>(await call(`/athletes/${fans[0]}/following`, viewer));
    expect(following).toEqual({
      items: [{ athlete: { id: star, displayName: "Étoile", avatarUrl: null }, viewerFollowStatus: "none" }],
      nextCursor: null,
    });

    for (const bad of ["nope", Buffer.from("2026-11-03|not-a-uuid").toString("base64url")]) {
      const response = await call(`/athletes/${star}/followers?cursor=${bad}`, viewer);
      expect(response.status).toBe(422);
      expect(await errorCode(response)).toBe("invalid_cursor");
    }
    expect((await call(`/athletes/${star}/following?limit=51`, viewer)).status).toBe(422);
  });

  it("lists, refuses and cancels requests, removes followers and unfollows, all idempotently", async () => {
    const me = await athlete();
    const asker = await athlete("Demandeur");
    const canceller = await athlete();
    const fan = await athlete();
    await follow(fan, me);
    await call("/me/follow-settings", me, "PUT", { approveFollowers: true });
    await follow(canceller, me);
    await follow(asker, me);

    const requests = await json<FollowRequestListResponse>(await call("/me/follow-requests", me));
    expect(requests.nextCursor).toBeNull();
    expect(requests.items.map((item) => item.athlete.id)).toEqual([asker, canceller]);
    expect(requests.items[0]).toMatchObject({
      athlete: { id: asker, displayName: "Demandeur", avatarUrl: null },
      viewerFollowStatus: "none",
    });
    expect(Number.isNaN(Date.parse(requests.items[0]!.requestedAt))).toBe(false);

    for (let attempt = 0; attempt < 2; attempt += 1) {
      expect((await call(`/me/follow-requests/${asker}`, me, "DELETE")).status).toBe(204);
      expect(await json<FollowResponse>(await call(`/athletes/${me}/follow`, canceller, "DELETE"))).toEqual({
        athleteId: me,
        viewerFollowStatus: "none",
        followerCount: 1,
      });
    }
    expect((await json<FollowRequestListResponse>(await call("/me/follow-requests", me))).items).toEqual([]);

    // Refusing or cancelling never touches an accepted follower; removing one does.
    expect((await call(`/me/follow-requests/${fan}`, me, "DELETE")).status).toBe(204);
    expect((await json<FollowListResponse>(await call(`/athletes/${me}/followers`, me))).items).toHaveLength(1);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      expect((await call(`/me/followers/${fan}`, me, "DELETE")).status).toBe(204);
    }
    expect((await json<FollowListResponse>(await call(`/athletes/${me}/followers`, me))).items).toEqual([]);

    await call("/me/follow-settings", me, "PUT", { approveFollowers: false });
    await follow(fan, me);
    expect(await json<FollowResponse>(await call(`/athletes/${me}/follow`, fan, "DELETE"))).toEqual({
      athleteId: me,
      viewerFollowStatus: "none",
      followerCount: 0,
    });
  });

  it("needs a session", async () => {
    const target = await athlete();
    expect((await fetch(`${baseUrl}/v1/athletes/${target}/follow`, { method: "PUT" })).status).toBe(401);
    expect((await fetch(`${baseUrl}/v1/me/follow-requests`)).status).toBe(401);
  });
});
