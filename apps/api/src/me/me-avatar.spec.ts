import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import type { AvatarUploadUrlResponse, MeResponse, SetAvatarResponse } from "@repo/contracts";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SocialModule } from "@repo/core/social";
import { StorageModule, StorageService } from "@repo/core/storage";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { UsersModule, UsersService } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";
import { InMemoryStorage } from "../testing/in-memory-storage.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { MeAvatarController } from "./me-avatar.controller.js";
import { MeController } from "./me.controller.js";

/**
 * The Avatar routes (ADR-037 §2) over real HTTP and Postgres, the bucket in memory (ADR-024 §2):
 * `POST /v1/me/avatar/upload-url`, `PUT /v1/me/avatar`, `DELETE /v1/me/avatar`, and the signed
 * `avatarUrl` of `GET /v1/me`. Sessions come from `x-test-user` through a fake `AuthService`.
 */
describe("Avatar routes (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  const storage = new InMemoryStorage();
  const athletes: string[] = [];

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function newAthlete(): Promise<string> {
    const id = randomUUID();
    athletes.push(id);
    await sql('insert into "user" (id, name, email, image) values ($1, $2, $3, $4)', [
      id,
      "Léa Martin",
      `${id}@test.local`,
      "https://lh3.googleusercontent.test/photo.jpg",
    ]);
    return id;
  }

  function call(user: string, method: string, path: string, body?: unknown) {
    return fetch(`${baseUrl}/v1/me${path}`, {
      method,
      headers: { "x-test-user": user, ...(body === undefined ? {} : { "content-type": "application/json" }) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  async function avatarKeyOf(user: string): Promise<string | null> {
    const [row] = await sql("select avatar_key from users.user_profile where user_id = $1", [user]);
    return (row?.avatar_key as string | null | undefined) ?? null;
  }

  /** Asks for an upload URL, then "sends" a file of `sizeBytes` to the bucket. */
  async function uploaded(user: string, sizeBytes = 40_000): Promise<string> {
    const response = await call(user, "POST", "/avatar/upload-url", { sizeBytes });
    expect(response.status).toBe(201);
    const { avatarId } = (await response.json()) as AvatarUploadUrlResponse;
    storage.objects.set(`avatars/${user}/${avatarId}.jpg`, new Uint8Array(sizeBytes));
    return avatarId;
  }

  async function setAvatar(user: string, avatarId: string): Promise<SetAvatarResponse> {
    const response = await call(user, "PUT", "/avatar", { avatarId });
    expect(response.status).toBe(200);
    return (await response.json()) as SetAvatarResponse;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        AnalyticsModule.forRoot({}),
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
      controllers: [MeController, MeAvatarController],
      providers: [
        SessionGuard,
        AthleteIdentities,
        { provide: SubscriptionsService, useValue: { isPremium: async () => false } },
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? { userId, email: `${userId}@test.local`, name: "Léa Martin", role: "user", twoFactorEnabled: false }
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
    })
      .overrideProvider(StorageService)
      .useValue(storage)
      .compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1");
    baseUrl = await listenOnLoopback(app);
  }, 30_000);

  afterEach(() => {
    storage.failDeletes = false;
  });

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [athletes]);
    await app?.close();
  });

  describe("POST /v1/me/avatar/upload-url", () => {
    it("returns a 15-minute PUT to a new avatars/{userId}/{avatarId}.jpg with its size signed", async () => {
      const user = await newAthlete();
      const response = await call(user, "POST", "/avatar/upload-url", { sizeBytes: 52_000 });

      expect(response.status).toBe(201);
      const body = (await response.json()) as AvatarUploadUrlResponse;
      const url = new URL(body.uploadUrl);
      expect(url.pathname).toBe(`/avatars/${user}/${body.avatarId}.jpg`);
      expect(url.searchParams.get("Content-Length")).toBe("52000");
      expect(url.searchParams.get("X-Amz-Expires")).toBe("900");
      expect(Date.parse(body.expiresAt)).toBeGreaterThan(Date.now());
    });

    it("gives a new avatarId every time (immutable keys, ADR-037 §1)", async () => {
      const user = await newAthlete();
      expect(await uploaded(user)).not.toBe(await uploaded(user));
    });

    it("refuses a file over 1 MB or an empty one (422)", async () => {
      const user = await newAthlete();
      for (const sizeBytes of [1024 * 1024 + 1, 0]) {
        const response = await call(user, "POST", "/avatar/upload-url", { sizeBytes });
        expect(response.status).toBe(422);
      }
    });

    it("requires a session (401)", async () => {
      const response = await fetch(`${baseUrl}/v1/me/avatar/upload-url`, { method: "POST" });
      expect(response.status).toBe(401);
    });
  });

  describe("PUT /v1/me/avatar", () => {
    it("stores the uploaded object as the Avatar and answers the identity with a 7-day signed URL", async () => {
      const user = await newAthlete();
      const avatarId = await uploaded(user);

      const { athlete } = await setAvatar(user, avatarId);

      expect(athlete).toMatchObject({ id: user, displayName: "Léa Martin" });
      const url = new URL(athlete.avatarUrl ?? "");
      expect(url.pathname).toBe(`/avatars/${user}/${avatarId}.jpg`);
      expect(url.searchParams.get("X-Amz-Expires")).toBe("604800");
      expect(await avatarKeyOf(user)).toBe(`avatars/${user}/${avatarId}.jpg`);
    });

    it("refuses an object that is not in the bucket (409 avatar_missing)", async () => {
      const user = await newAthlete();
      const response = await call(user, "PUT", "/avatar", { avatarId: randomUUID() });

      expect(response.status).toBe(409);
      expect(await response.json()).toMatchObject({ error: { code: "avatar_missing" } });
      expect(await avatarKeyOf(user)).toBeNull();
    });

    it("refuses an object over 1 MB (409 avatar_too_large)", async () => {
      const user = await newAthlete();
      const avatarId = await uploaded(user);
      storage.objects.set(`avatars/${user}/${avatarId}.jpg`, new Uint8Array(1024 * 1024 + 1));

      const response = await call(user, "PUT", "/avatar", { avatarId });

      expect(response.status).toBe(409);
      expect(await response.json()).toMatchObject({ error: { code: "avatar_too_large" } });
      expect(await avatarKeyOf(user)).toBeNull();
    });

    it("refuses another athlete's object: the key is always under the caller's own folder", async () => {
      const owner = await newAthlete();
      const thief = await newAthlete();
      const avatarId = await uploaded(owner);

      const response = await call(thief, "PUT", "/avatar", { avatarId });

      expect(response.status).toBe(409);
      expect(await avatarKeyOf(thief)).toBeNull();
    });

    it("replaces the Avatar and deletes the old object", async () => {
      const user = await newAthlete();
      const first = await uploaded(user);
      await setAvatar(user, first);
      const second = await uploaded(user);

      await setAvatar(user, second);

      expect(await avatarKeyOf(user)).toBe(`avatars/${user}/${second}.jpg`);
      expect(storage.objects.has(`avatars/${user}/${first}.jpg`)).toBe(false);
      expect(storage.objects.has(`avatars/${user}/${second}.jpg`)).toBe(true);
    });

    it("keeps the object on a replay of the same avatarId", async () => {
      const user = await newAthlete();
      const avatarId = await uploaded(user);
      await setAvatar(user, avatarId);

      await setAvatar(user, avatarId);

      expect(storage.objects.has(`avatars/${user}/${avatarId}.jpg`)).toBe(true);
    });

    it("still answers 200 when the old object cannot be deleted (only logged)", async () => {
      const user = await newAthlete();
      const first = await uploaded(user);
      await setAvatar(user, first);
      const second = await uploaded(user);
      storage.failDeletes = true;

      await setAvatar(user, second);

      expect(await avatarKeyOf(user)).toBe(`avatars/${user}/${second}.jpg`);
    });

    it("refuses a body without a UUID avatarId (422)", async () => {
      const user = await newAthlete();
      const response = await call(user, "PUT", "/avatar", { avatarId: "../other/x" });
      expect(response.status).toBe(422);
    });
  });

  describe("DELETE /v1/me/avatar", () => {
    it("removes the Avatar and deletes its object (204), then the athlete has no avatarUrl", async () => {
      const user = await newAthlete();
      const avatarId = await uploaded(user);
      await setAvatar(user, avatarId);

      const response = await call(user, "DELETE", "/avatar");

      expect(response.status).toBe(204);
      expect(await avatarKeyOf(user)).toBeNull();
      expect(storage.objects.has(`avatars/${user}/${avatarId}.jpg`)).toBe(false);
      const me = (await (await call(user, "GET", "")).json()) as MeResponse;
      expect(me.avatarUrl).toBeUndefined();
    });

    it("answers 204 without an Avatar", async () => {
      const user = await newAthlete();
      expect((await call(user, "DELETE", "/avatar")).status).toBe(204);
    });

    it("still answers 204 when the object cannot be deleted (only logged)", async () => {
      const user = await newAthlete();
      await setAvatar(user, await uploaded(user));
      storage.failDeletes = true;

      expect((await call(user, "DELETE", "/avatar")).status).toBe(204);
      expect(await avatarKeyOf(user)).toBeNull();
    });
  });

  describe("GET /v1/me", () => {
    it("has no avatarUrl without avatar_key, even with a Google photo in user.image", async () => {
      const user = await newAthlete();
      const me = (await (await call(user, "GET", "")).json()) as MeResponse;
      expect(me).not.toHaveProperty("avatarUrl");
    });

    it("signs avatarUrl for 7 days and never shows the object key", async () => {
      const user = await newAthlete();
      const avatarId = await uploaded(user);
      await setAvatar(user, avatarId);

      const response = await call(user, "GET", "");
      const text = await response.text();
      const me = JSON.parse(text) as MeResponse;

      expect(new URL(me.avatarUrl ?? "").searchParams.get("X-Amz-Expires")).toBe("604800");
      expect(text).not.toContain('"avatars/');
      expect(text).not.toContain("avatarKey");
    });
  });

  describe("UsersService.setAvatar (used by the Google photo copy)", () => {
    it("with onlyIfAbsent, keeps an Avatar already set and leaves both objects alone", async () => {
      const user = await newAthlete();
      const current = await uploaded(user);
      await setAvatar(user, current);
      const copied = await uploaded(user);

      const stored = await app.get(UsersService).setAvatar(user, copied, { onlyIfAbsent: true });

      expect(stored).toBe(false);
      expect(await avatarKeyOf(user)).toBe(`avatars/${user}/${current}.jpg`);
      expect(storage.objects.has(`avatars/${user}/${current}.jpg`)).toBe(true);
    });

    it("with onlyIfAbsent, stores the Avatar of an athlete who has none", async () => {
      const user = await newAthlete();
      const copied = await uploaded(user);

      expect(await app.get(UsersService).setAvatar(user, copied, { onlyIfAbsent: true })).toBe(true);
      expect(await avatarKeyOf(user)).toBe(`avatars/${user}/${copied}.jpg`);
    });
  });
});
