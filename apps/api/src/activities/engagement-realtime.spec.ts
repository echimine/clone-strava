import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { ActivitiesModule } from "@repo/core/activities";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { EngagementModule } from "@repo/core/engagement";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { RealtimeBridgeModule } from "@repo/core/realtime";
import { StorageModule } from "@repo/core/storage";
import { UsersModule } from "@repo/core/users";
import {
  COMMENT_CREATED,
  COMMENT_DELETED,
  COMMENT_UPDATED,
  KUDOS_CHANGED,
  activityTopic,
  createRedisEventSource,
  type RealtimeChannelMessage,
  type RealtimeEventSource,
} from "@repo/realtime";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { CommentAssembler } from "./comment-assembler.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { CommentsController } from "./comments.controller.js";
import { KudosAssembler } from "./kudos-assembler.js";
import { KudosController } from "./kudos.controller.js";

/**
 * Kudos and comments relayed live on `activity:{id}` (ADR-034 §4, §5) over
 * real HTTP, Postgres and Redis, read back from the channel the gateways
 * listen to.
 */
describe("engagement realtime relay (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  let bullConnection: Redis;
  let source: RealtimeEventSource;
  const received: RealtimeChannelMessage[] = [];
  const author = randomUUID();
  const fan = randomUUID();

  async function sql(text: string, params: unknown[] = []) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  function call(path: string, user: string, method: string, body?: unknown) {
    return fetch(`${baseUrl}/v1/activities${path}`, {
      method,
      headers: { "content-type": "application/json", "x-test-user": user },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  async function insertActivity() {
    const id = randomUUID();
    await sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values ($1, $2, 'run', 'Sortie', now() - interval '2 hours', now() - interval '1 hour', 'public', 'processed')`,
      [id, author],
    );
    return id;
  }

  /** Messages on one Activity's topic (other spec files publish on the same channel). */
  function messagesOn(activityId: string) {
    return received
      .filter((message) => message.topics.includes(activityTopic(activityId)))
      .map((message) => ({ topics: message.topics, t: message.envelope.t, data: message.envelope.data }));
  }

  /** Lets an event that should not come a chance to arrive. */
  const settle = () => new Promise((resolve) => setTimeout(resolve, 200));

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
        RealtimeBridgeModule,
        ActivitiesModule,
        EngagementModule,
        UsersModule,
      ],
      controllers: [KudosController, CommentsController],
      providers: [
        SessionGuard,
        CommentAssembler,
        AthleteIdentities,
        KudosAssembler,
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
    for (const id of [author, fan]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Athlete", `${id}@test.local`]);
    }

    source = createRedisEventSource(new Redis(TEST_REDIS_URL));
    source.onMessage((message) => received.push(message));
    await source.subscribe();
  }, 30_000);

  afterAll(async () => {
    await source?.close();
    await sql('delete from "user" where id = any($1)', [[author, fan]]);
    await app?.close();
    await bullConnection?.quit();
  });

  it("relays kudos.changed once per real change, never for a repeated PUT or DELETE", async () => {
    const activityId = await insertActivity();

    expect((await call(`/${activityId}/kudos`, fan, "PUT")).status).toBe(200);
    expect((await call(`/${activityId}/kudos`, fan, "PUT")).status).toBe(200);
    await vi.waitFor(() => expect(messagesOn(activityId)).toHaveLength(1), { timeout: 3_000 });
    expect((await call(`/${activityId}/kudos`, fan, "DELETE")).status).toBe(200);
    expect((await call(`/${activityId}/kudos`, fan, "DELETE")).status).toBe(200);
    await vi.waitFor(() => expect(messagesOn(activityId)).toHaveLength(2), { timeout: 3_000 });
    await settle();

    const kudos = { topics: [activityTopic(activityId)], t: KUDOS_CHANGED, data: { activityId } };
    expect(messagesOn(activityId)).toEqual([kudos, kudos]);
  });

  it("relays comment.created, comment.updated and comment.deleted with ids only", async () => {
    const activityId = await insertActivity();
    const commentId = randomUUID();

    expect((await call(`/${activityId}/comments`, fan, "POST", { id: commentId, body: "Bravo !" })).status).toBe(201);
    // A replay writes nothing and relays nothing (ADR-034 §4).
    expect((await call(`/${activityId}/comments`, fan, "POST", { id: commentId, body: "Bravo !" })).status).toBe(200);
    expect((await call(`/${activityId}/comments/${commentId}`, fan, "PATCH", { body: "Superbe !" })).status).toBe(200);
    expect((await call(`/${activityId}/comments/${commentId}`, author, "DELETE")).status).toBe(204);
    await vi.waitFor(() => expect(messagesOn(activityId)).toHaveLength(3), { timeout: 3_000 });
    await settle();

    const on = (t: string) => ({ topics: [activityTopic(activityId)], t, data: { activityId, commentId } });
    expect(messagesOn(activityId)).toEqual([on(COMMENT_CREATED), on(COMMENT_UPDATED), on(COMMENT_DELETED)]);
  });
});
