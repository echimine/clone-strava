import { randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { DynamicModule, INestApplication, Provider, Type } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import type { NextFunction, Request, Response as ExpressResponse } from "express";
import { Redis } from "ioredis";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuditModule } from "@repo/core/audit";
import { AuthService } from "@repo/core/auth";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { StorageModule, StorageService } from "@repo/core/storage";
import { AdminGuard } from "../auth/admin.guard.js";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { InMemoryStorage } from "./in-memory-storage.js";
import { listenOnLoopback } from "./listen-on-loopback.js";

/** Header naming the signed-in user of a request; `x-test-role: user` makes them a plain athlete. */
export const TEST_USER_HEADER = "x-test-user";
export const TEST_ROLE_HEADER = "x-test-role";

export interface AdminTestApp {
  app: INestApplication;
  baseUrl: string;
  storage: InMemoryStorage;
  /** Raw SQL on the test database. */
  sql: <Row = Record<string, unknown>>(text: string, params?: unknown[]) => Promise<Row[]>;
  /**
   * Calls `/v1<path>` as `userId`: a strong admin session (password + 2FA) unless `role` says
   * otherwise. `x-request-id` is copied to `request.id`, as `pino-http` does in production.
   */
  call: (
    path: string,
    userId: string,
    init?: { method?: string; body?: unknown; role?: "admin" | "user"; requestId?: string },
  ) => Promise<Response>;
  /** Inserts an athlete (`user` row, name `name`) and returns their id. */
  seedUser: (name: string, options?: { id?: string; role?: "admin" | "user" }) => Promise<string>;
  /** Deletes the users seeded here (cascades) and closes the app. */
  close: () => Promise<void>;
}

/**
 * Boots the `/v1/admin/*` controllers under test over real HTTP, Postgres and Redis (ADR-024 §2),
 * behind the real `SessionGuard` + `AdminGuard`, with the global pipe, serializer and error filter
 * of `AppModule`. Sessions come from `x-test-user` through a fake `AuthService` (its
 * `getPublicIdentities` reads the `user` table); S3 is an `InMemoryStorage`. `AuditModule` is
 * always there, since every admin write is `@Audited`.
 *
 * Specs needing real Better Auth admin calls (`banUser`, `setRole`…) use `bootstrapTestAuthApp`.
 */
export async function bootstrapAdminTestApp(options: {
  imports?: (Type | DynamicModule)[];
  controllers: Type[];
  providers?: Provider[];
  /** Extra methods on the fake `AuthService`. */
  authService?: Record<string, unknown>;
}): Promise<AdminTestApp> {
  await ensureTestDatabaseMigrated();
  const storage = new InMemoryStorage();
  const bullConnection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
  const seeded: string[] = [];
  let database: Database | undefined;

  const sql = async <Row,>(text: string, params: unknown[] = []) =>
    (await database!.$client.query(text, params)).rows as Row[];

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
      AuditModule,
      ...(options.imports ?? []),
    ],
    controllers: options.controllers,
    providers: [
      SessionGuard,
      AdminGuard,
      {
        provide: AuthService,
        useValue: {
          getSession: async (headers: Headers) => {
            const userId = headers.get(TEST_USER_HEADER);
            if (!userId) {
              return null;
            }
            const isAdmin = headers.get(TEST_ROLE_HEADER) !== "user";
            return {
              userId,
              email: `${userId}@test.local`,
              name: "Test",
              role: isAdmin ? "admin" : "user",
              twoFactorEnabled: isAdmin,
              authMethod: isAdmin ? "password_2fa" : "email_otp",
            };
          },
          getPublicIdentities: (userIds: string[]) =>
            sql('select id as "userId", name from "user" where id = any($1)', [userIds]),
          ...options.authService,
        },
      },
      ...(options.providers ?? []),
      { provide: APP_PIPE, useClass: ZodValidationPipe },
      { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
      { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    ],
  })
    .overrideProvider(StorageService)
    .useValue(storage)
    .compile();

  const app = moduleRef.createNestApplication();
  // `pino-http`'s `genReqId` in production (`src/logging`): the request id comes from `x-request-id`.
  app.use((request: Request, _response: ExpressResponse, next: NextFunction) => {
    const header = request.headers["x-request-id"];
    if (typeof header === "string") {
      request.id = header;
    }
    next();
  });
  app.setGlobalPrefix("v1");
  const baseUrl = await listenOnLoopback(app);
  database = app.get<Database>(DATABASE);

  return {
    app,
    baseUrl,
    storage,
    sql,
    call: (path, userId, init = {}) =>
      fetch(`${baseUrl}/v1${path}`, {
        method: init.method ?? "GET",
        headers: {
          "content-type": "application/json",
          [TEST_USER_HEADER]: userId,
          ...(init.role ? { [TEST_ROLE_HEADER]: init.role } : {}),
          ...(init.requestId ? { "x-request-id": init.requestId } : {}),
        },
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
      }),
    seedUser: async (name, seedOptions = {}) => {
      const id = seedOptions.id ?? randomUUID();
      await sql('insert into "user" (id, name, email, role) values ($1, $2, $3, $4)', [
        id,
        name,
        `${id}@test.local`,
        seedOptions.role ?? "user",
      ]);
      seeded.push(id);
      return id;
    },
    close: async () => {
      if (seeded.length > 0) {
        await sql('delete from "user" where id = any($1)', [seeded]);
      }
      await app.close();
      await bullConnection.quit().catch(() => undefined);
    },
  };
}
