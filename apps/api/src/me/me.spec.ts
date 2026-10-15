import { randomUUID } from "node:crypto";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { MeResponse } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { UsersModule } from "@repo/core/users";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { MeController } from "./me.controller.js";

/**
 * `GET /v1/me` over real HTTP and Postgres (ADR-024 §2): the default
 * visibility of a new Activity comes from `user_profile` (ADR-031 §13).
 * Sessions come from `x-test-user` through a fake `AuthService`.
 */
describe("GET /v1/me (integration)", () => {
  let app: INestApplication;
  let baseUrl: string;
  const withProfile = randomUUID();
  const withoutProfile = randomUUID();

  async function sql(text: string, params: unknown[]) {
    return (await app.get<Database>(DATABASE).$client.query(text, params)).rows;
  }

  async function me(user: string): Promise<MeResponse> {
    const response = await fetch(`${baseUrl}/v1/me`, { headers: { "x-test-user": user } });
    expect(response.status).toBe(200);
    return (await response.json()) as MeResponse;
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        UsersModule,
      ],
      controllers: [MeController],
      providers: [
        SessionGuard,
        { provide: SubscriptionsService, useValue: { isPremium: async () => false } },
        {
          provide: AuthService,
          useValue: {
            getSession: async (headers: Headers) => {
              const userId = headers.get("x-test-user");
              return userId
                ? {
                    userId,
                    email: `${userId}@test.local`,
                    name: "Test",
                    role: "user",
                    twoFactorEnabled: false,
                  }
                : null;
            },
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

    for (const id of [withProfile, withoutProfile]) {
      await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [id, "Test", `${id}@test.local`]);
    }
    await sql("insert into users.user_profile (user_id, default_visibility) values ($1, 'followers')", [
      withProfile,
    ]);
  }, 30_000);

  afterAll(async () => {
    await sql('delete from "user" where id = any($1)', [[withProfile, withoutProfile]]);
    await app?.close();
  });

  it("exposes the default visibility of the athlete's profile", async () => {
    expect(await me(withProfile)).toMatchObject({ id: withProfile, defaultVisibility: "followers" });
  });

  it("falls back to public without a profile row", async () => {
    expect((await me(withoutProfile)).defaultVisibility).toBe("public");
  });
});
