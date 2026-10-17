import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitter2, EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import type { ActivityComment, ListCommentsResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule, EngagementService } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { CommentAssembler } from "./comment-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { CommentsController } from "./comments.controller.js";

/**
 * `/v1/activities/:id/comments` over real HTTP and Postgres (ADR-024 §2
 * integration tier, ADR-034 §2-4). Sessions come from `x-test-user`
 * through a fake `AuthService` (see `feed.spec.ts`); domain events are
 * observed on the real `EventEmitter2`.
 */
describe("/v1/activities/:id/comments (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  let emit: MockInstance<EventEmitter2["emit"]>;
  const author = randomUUID();
  const commenter = randomUUID();
  const third = randomUUID();
  const stranger = randomUUID();

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, init: { method?: string; body?: unknown } = {}) {
    return fetch(`${baseUrl}/v1${path}`, {
      method: init.method ?? "GET",
      headers: { "content-type": "application/json", "x-test-user": user },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
    });
  }

  async function insertActivity(userId: string, options: { visibility?: string; status?: string } = {}) {
    const id = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now() - interval '2 hours', now() - interval '1 hour', $3, $4)`,
      [id, userId, options.visibility ?? "public", options.status ?? "processed"],
    );
    return id;
  }

  function post(activityId: string, user: string, body: unknown) {
    return call(`/activities/${activityId}/comments`, user, { method: "POST", body });
  }

  async function addComment(activityId: string, user: string, body = "Bravo !") {
    const response = await post(activityId, user, { id: randomUUID(), body });
    expect(response.status).toBe(201);
    return (await response.json()) as ActivityComment;
  }

  async function list(activityId: string, user: string, query = "") {
    const response = await call(`/activities/${activityId}/comments${query}`, user);
    expect(response.status).toBe(200);
    return (await response.json()) as ListCommentsResponse;
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  function emitted(name: string) {
    return emit.mock.calls.filter(([event]) => event === name).map(([, payload]) => payload);
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
      controllers: [CommentsController],
      providers: [
        SessionGuard,
        CommentAssembler,
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
    emit = vi.spyOn(app.get(EventEmitter2), "emit");

    for (const [index, id] of [author, commenter, third, stranger].entries()) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, `User ${index}`, `${id}@test.local`]);
    }
    await sql(
      "insert into users.user_profile (user_id, first_name, last_name, avatar_url) values ($1, 'Camille', 'Martin', 'https://cdn.test/c.png')",
      [commenter],
    );
  }, 30_000);

  beforeEach(() => emit.mockClear());

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [[author, commenter, third, stranger]]);
    await app.close();
    await bullConnection.quit();
  });

  it("adds a comment and lists it with its author", async () => {
    const activityId = await insertActivity(author);
    const id = randomUUID();

    const response = await post(activityId, commenter, { id, body: "  Belle sortie !  " });
    expect(response.status).toBe(201);
    const created = (await response.json()) as ActivityComment;
    expect(created).toEqual({
      id,
      body: "Belle sortie !",
      createdAt: expect.any(String),
      updatedAt: null,
      author: { id: commenter, displayName: "Camille Martin", avatarUrl: "https://cdn.test/c.png" },
      viewerCanEdit: true,
      viewerCanDelete: true,
    });

    expect(await list(activityId, author)).toEqual({
      items: [{ ...created, viewerCanEdit: false, viewerCanDelete: true }],
      previousCursor: null,
    });
    expect(await list(activityId, third)).toEqual({
      items: [{ ...created, viewerCanEdit: false, viewerCanDelete: false }],
      previousCursor: null,
    });
  });

  describe("every route", () => {
    /** One request per route on `activityId`, `commentId` being any comment id. */
    function everyRoute(activityId: string, commentId: string, user: string) {
      const base = `/activities/${activityId}/comments`;
      return Promise.all([
        call(base, user),
        call(`${base}/${commentId}`, user),
        call(base, user, { method: "POST", body: { id: randomUUID(), body: "Salut" } }),
        call(`${base}/${commentId}`, user, { method: "PATCH", body: { body: "Salut" } }),
        call(`${base}/${commentId}`, user, { method: "DELETE" }),
      ]);
    }

    it("answers 404 activity_not_found when the viewer cannot see the Activity", async () => {
      const privateId = await insertActivity(author, { visibility: "private" });
      const followersId = await insertActivity(author, { visibility: "followers" });
      const comment = await addComment(privateId, author, "Note perso");

      for (const activityId of [privateId, followersId, randomUUID()]) {
        for (const response of await everyRoute(activityId, comment.id, stranger)) {
          expect(response.status).toBe(404);
          expect(await errorCode(response)).toBe("activity_not_found");
        }
      }
      expect((await list(privateId, author)).items).toHaveLength(1);
    });

    it("answers 409 activity_not_commentable on an Activity that is not processed", async () => {
      for (const status of ["pending", "processing", "failed"]) {
        const activityId = await insertActivity(author, { status });
        for (const response of await everyRoute(activityId, randomUUID(), author)) {
          expect(response.status).toBe(409);
          expect(await errorCode(response)).toBe("activity_not_commentable");
        }
        // Not visible to anyone else (ADR-029): their 404 wins.
        expect((await call(`/activities/${activityId}/comments`, stranger)).status).toBe(404);
      }
      expect(emitted("engagement.comment.added")).toEqual([]);
    });
  });

  describe("GET list", () => {
    async function insertComments(activityId: string, count: number) {
      const ids: string[] = [];
      for (let i = 0; i < count; i++) {
        const id = randomUUID();
        ids.push(id);
        await sql(
          `insert into engagement.comment (id, activity_id, user_id, body, created_at)
           values ($1, $2, $3, $4, now() - make_interval(secs => $5))`,
          [id, activityId, commenter, `Commentaire ${i}`, 1000 - i],
        );
      }
      return ids; // oldest first
    }

    it("returns the newest page in chronological order, then older pages through `before`", async () => {
      const activityId = await insertActivity(author);
      const ids = await insertComments(activityId, 5);

      const newest = await list(activityId, third, "?limit=2");
      expect(newest.items.map((item) => item.id)).toEqual(ids.slice(3));
      expect(newest.previousCursor).toEqual(expect.any(String));

      const middle = await list(activityId, third, `?limit=2&before=${newest.previousCursor}`);
      expect(middle.items.map((item) => item.id)).toEqual(ids.slice(1, 3));

      const oldest = await list(activityId, third, `?limit=2&before=${middle.previousCursor}`);
      expect(oldest).toMatchObject({ previousCursor: null });
      expect(oldest.items.map((item) => item.id)).toEqual(ids.slice(0, 1));
    });

    it("defaults to and caps at 50 comments, skipping deleted ones", async () => {
      const activityId = await insertActivity(author);
      const ids = await insertComments(activityId, 52);
      await sql("update engagement.comment set deleted_at = now() where id = $1", [ids[51]]);

      const page = await list(activityId, third);
      expect(page.items.map((item) => item.id)).toEqual(ids.slice(1, 51));
      expect(page.previousCursor).toEqual(expect.any(String));
      expect((await list(activityId, third, `?before=${page.previousCursor}`)).items.map((item) => item.id)).toEqual(
        ids.slice(0, 1),
      );

      expect((await call(`/activities/${activityId}/comments?limit=51`, third)).status).toBe(422);
      const badCursor = await call(`/activities/${activityId}/comments?before=nope`, third);
      expect(badCursor.status).toBe(422);
      expect(await errorCode(badCursor)).toBe("invalid_cursor");
    });

    it("keeps comments created in the same millisecond apart in the keyset", async () => {
      const activityId = await insertActivity(author);
      const ids = [randomUUID(), randomUUID(), randomUUID()].sort();
      for (const id of ids) {
        await sql(
          "insert into engagement.comment (id, activity_id, user_id, body, created_at) values ($1, $2, $3, 'Pile', '2026-10-16T10:00:00.000Z')",
          [id, activityId, commenter],
        );
      }

      const first = await list(activityId, third, "?limit=2");
      const second = await list(activityId, third, `?limit=2&before=${first.previousCursor}`);
      expect([...second.items, ...first.items].map((item) => item.id)).toEqual(ids);
      expect(second.previousCursor).toBeNull();
    });
  });

  describe("GET one", () => {
    it("returns one comment, 404 comment_not_found when unknown or on another Activity", async () => {
      const activityId = await insertActivity(author);
      const otherActivityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);

      const response = await call(`/activities/${activityId}/comments/${comment.id}`, author);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ...comment, viewerCanEdit: false, viewerCanDelete: true });

      for (const path of [`/activities/${activityId}/comments/${randomUUID()}`, `/activities/${otherActivityId}/comments/${comment.id}`]) {
        const missing = await call(path, author);
        expect(missing.status).toBe(404);
        expect(await errorCode(missing)).toBe("comment_not_found");
      }
    });
  });

  describe("PATCH", () => {
    function patch(activityId: string, commentId: string, user: string, body: unknown) {
      return call(`/activities/${activityId}/comments/${commentId}`, user, { method: "PATCH", body });
    }

    it("lets the comment's author edit it, sets updatedAt and emits engagement.comment.edited", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);
      emit.mockClear();

      const response = await patch(activityId, comment.id, commenter, { body: "  Corrigé  " });
      expect(response.status).toBe(200);
      const edited = (await response.json()) as ActivityComment;
      expect(edited).toEqual({ ...comment, body: "Corrigé", updatedAt: expect.any(String) });
      expect(Date.parse(edited.updatedAt!)).toBeGreaterThanOrEqual(Date.parse(comment.createdAt));
      expect(emitted("engagement.comment.edited")).toEqual([{ commentId: comment.id, activityId, userId: commenter }]);
      expect((await list(activityId, author)).items[0]).toMatchObject({ body: "Corrigé", updatedAt: edited.updatedAt });
    });

    it("refuses anyone but the comment's author, the Activity's author included", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);
      emit.mockClear();

      for (const user of [author, third]) {
        const response = await patch(activityId, comment.id, user, { body: "Pas à toi" });
        expect(response.status).toBe(403);
        expect(await errorCode(response)).toBe("not_comment_author");
      }
      expect(emitted("engagement.comment.edited")).toEqual([]);
    });

    it("answers 404 comment_not_found for an unknown or deleted comment, 422 for an invalid body", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);

      expect((await patch(activityId, comment.id, commenter, { body: " " })).status).toBe(422);
      expect((await patch(activityId, comment.id, commenter, { body: "x".repeat(1001) })).status).toBe(422);
      const unknown = await patch(activityId, randomUUID(), commenter, { body: "Ok" });
      expect(unknown.status).toBe(404);
      expect(await errorCode(unknown)).toBe("comment_not_found");

      await sql("update engagement.comment set deleted_at = now() where id = $1", [comment.id]);
      const deleted = await patch(activityId, comment.id, commenter, { body: "Ok" });
      expect(deleted.status).toBe(404);
      expect(await errorCode(deleted)).toBe("comment_not_found");
    });
  });

  describe("DELETE", () => {
    function remove(activityId: string, commentId: string, user: string) {
      return call(`/activities/${activityId}/comments/${commentId}`, user, { method: "DELETE" });
    }

    async function commentCount(activityId: string) {
      return (await app.get(EngagementService).getCounts([activityId])).get(activityId)!.commentCount;
    }

    it("lets the comment's author delete it: gone from the list, the comment and the count", async () => {
      const activityId = await insertActivity(author);
      const kept = await addComment(activityId, third, "Reste");
      const comment = await addComment(activityId, commenter);
      expect(await commentCount(activityId)).toBe(2);
      emit.mockClear();

      const response = await remove(activityId, comment.id, commenter);
      expect(response.status).toBe(204);
      expect(emitted("engagement.comment.deleted")).toEqual([{ commentId: comment.id, activityId, userId: commenter }]);
      expect((await list(activityId, author)).items.map((item) => item.id)).toEqual([kept.id]);
      expect(await commentCount(activityId)).toBe(1);
      const gone = await call(`/activities/${activityId}/comments/${comment.id}`, commenter);
      expect(gone.status).toBe(404);
      expect(await errorCode(gone)).toBe("comment_not_found");
    });

    it("lets the Activity's author delete someone else's comment", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);
      emit.mockClear();

      expect((await remove(activityId, comment.id, author)).status).toBe(204);
      expect(emitted("engagement.comment.deleted")).toEqual([{ commentId: comment.id, activityId, userId: author }]);
    });

    it("refuses a third party with 403", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);
      emit.mockClear();

      const response = await remove(activityId, comment.id, third);
      expect(response.status).toBe(403);
      expect(await errorCode(response)).toBe("not_allowed_to_delete_comment");
      expect(emitted("engagement.comment.deleted")).toEqual([]);
      expect((await list(activityId, author)).items).toHaveLength(1);
    });

    it("is idempotent: a repeated DELETE answers 204 and emits nothing", async () => {
      const activityId = await insertActivity(author);
      const comment = await addComment(activityId, commenter);
      expect((await remove(activityId, comment.id, commenter)).status).toBe(204);
      emit.mockClear();

      expect((await remove(activityId, comment.id, commenter)).status).toBe(204);
      expect(emitted("engagement.comment.deleted")).toEqual([]);
    });

    it("answers 404 comment_not_found for an unknown comment or one of another Activity", async () => {
      const activityId = await insertActivity(author);
      const otherActivityId = await insertActivity(author);
      const comment = await addComment(otherActivityId, commenter);

      for (const commentId of [randomUUID(), comment.id]) {
        const response = await remove(activityId, commentId, author);
        expect(response.status).toBe(404);
        expect(await errorCode(response)).toBe("comment_not_found");
      }
    });
  });

  describe("POST", () => {
    it("emits engagement.comment.added after the commit, and nothing on a replay", async () => {
      const activityId = await insertActivity(author);
      const body = { id: randomUUID(), body: "Premier !" };

      const first = await post(activityId, commenter, body);
      expect(first.status).toBe(201);
      const created = (await first.json()) as ActivityComment;
      expect(emitted("engagement.comment.added")).toEqual([{ commentId: body.id, activityId, userId: commenter }]);
      emit.mockClear();

      const replay = await post(activityId, commenter, { ...body, body: "Texte rejoué différent" });
      expect(replay.status).toBe(200);
      expect(await replay.json()).toEqual(created);
      expect(emitted("engagement.comment.added")).toEqual([]);
      expect((await list(activityId, commenter)).items.map((item) => item.body)).toEqual(["Premier !"]);
    });

    it("refuses an id already used by someone else or on another Activity", async () => {
      const activityId = await insertActivity(author);
      const otherActivityId = await insertActivity(author);
      const id = randomUUID();
      expect((await post(activityId, commenter, { id, body: "À moi" })).status).toBe(201);
      emit.mockClear();

      const byOther = await post(activityId, third, { id, body: "Volé" });
      expect(byOther.status).toBe(409);
      expect(await errorCode(byOther)).toBe("comment_id_conflict");

      const elsewhere = await post(otherActivityId, commenter, { id, body: "Ailleurs" });
      expect(elsewhere.status).toBe(409);
      expect(await errorCode(elsewhere)).toBe("comment_id_conflict");
      expect(emitted("engagement.comment.added")).toEqual([]);
    });

    it("accepts a body of 1 to 1,000 characters once trimmed", async () => {
      const activityId = await insertActivity(author);

      expect((await post(activityId, commenter, { id: randomUUID(), body: "x" })).status).toBe(201);
      expect((await post(activityId, commenter, { id: randomUUID(), body: "é".repeat(1000) })).status).toBe(201);
      for (const body of ["", "   \n ", "x".repeat(1001)]) {
        const response = await post(activityId, commenter, { id: randomUUID(), body });
        expect(response.status).toBe(422);
        expect(await errorCode(response)).toBe("validation_error");
      }
      expect((await post(activityId, commenter, { body: "Sans id" })).status).toBe(422);
    });
  });
});
