import { randomInt, randomUUID } from "node:crypto";
import { BullModule } from "@nestjs/bullmq";
import type { DynamicModule, INestApplication, Provider, Type } from "@nestjs/common";
import { RequestMethod } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { EventEmitterModule } from "@nestjs/event-emitter";
import { Test } from "@nestjs/testing";
import { toNodeHandler } from "better-auth/node";
import express, { type Express } from "express";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { AnalyticsModule } from "@repo/core/analytics";
import { AuditModule } from "@repo/core/audit";
import { AUTH_INSTANCE, AuthModule as CoreAuthModule } from "@repo/core/auth";
import { GeocodingModule } from "@repo/core/geocoding";
import { CoreInfrastructureModule, DATABASE, type Database } from "@repo/core/infrastructure";
import { NotificationsService } from "@repo/core/notifications";
import { StorageModule, StorageService } from "@repo/core/storage";
import { AdminGuard } from "../auth/admin.guard.js";
import { SessionGuard } from "../auth/session.guard.js";
import { ensureTestDatabaseMigrated, TEST_ADMIN_ORIGIN, TEST_DATABASE_URL, TEST_REDIS_URL } from "../auth/test-auth-app.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { InMemoryStorage } from "./in-memory-storage.js";
import { listenOnLoopback } from "./listen-on-loopback.js";
import { computeTotpCode } from "./totp.js";

const PASSWORD = "correcthorsebatterystaple123";

/** A signed-up account and its session cookie. */
export interface TestAccount {
  userId: string;
  email: string;
  cookie: string;
}

export interface AdminAuthTestApp {
  app: INestApplication;
  baseUrl: string;
  storage: InMemoryStorage;
  /** Raw SQL on the test database. */
  sql: <Row = Record<string, unknown>>(text: string, params?: unknown[]) => Promise<Row[]>;
  /** `POST /api/auth<path>` (Better Auth), from a client IP of its own. */
  authPost: (path: string, body: unknown, options?: { cookie?: string; ip?: string }) => Promise<Response>;
  /** Calls `/v1<path>` with a session cookie. */
  call: (path: string, cookie: string, init?: { method?: string; body?: unknown }) => Promise<Response>;
  /** An Administrator with a strong session (password + TOTP), as the backoffice signs in. */
  createAdmin: (label: string) => Promise<TestAccount>;
  /**
   * An athlete signed up by password (the test instance only), with a session and a profile.
   * `@stravaclone.test` addresses also get the dev Sign-in code `000000`.
   */
  createAthlete: (label: string, profile?: { firstName?: string; lastName?: string; bio?: string }) => Promise<TestAccount>;
  close: () => Promise<void>;
}

/** A client IP of its own per call: Better Auth's rate limits count per `${ip}|${path}`. */
function freshIp(): string {
  return `10.${randomInt(1, 255)}.${randomInt(1, 255)}.${randomInt(1, 255)}`;
}

function sessionCookie(response: Response): string {
  const pair = response.headers
    .getSetCookie()
    .map((header) => header.split(";")[0] ?? "")
    .find((cookie) => cookie.split("=")[0]?.includes("session_token") && !cookie.endsWith("="));
  if (!pair) {
    throw new Error(`No session cookie (status ${response.status})`);
  }
  return pair;
}

/**
 * The backoffice controllers under test behind the **real** Better Auth (ADR-024 §2): sessions,
 * `SessionGuard` + `AdminGuard` and the admin plugin's `auth.api.*` calls (Ban, roles, sessions)
 * all run for real over Postgres and Redis, Better Auth mounted at `/api/auth/*` as `main.ts`
 * does. E-mails are a no-op, S3 an `InMemoryStorage`. Dev Sign-in codes are on.
 *
 * Specs with a fake session use `bootstrapAdminTestApp` instead.
 */
export async function bootstrapAdminAuthTestApp(options: {
  imports?: (Type | DynamicModule)[];
  controllers: Type[];
  providers?: Provider[];
  contactEmail?: string;
}): Promise<AdminAuthTestApp> {
  await ensureTestDatabaseMigrated();
  const storage = new InMemoryStorage();
  let database: Database | undefined;
  const sql = async <Row,>(text: string, params: unknown[] = []) =>
    (await database!.$client.query(text, params)).rows as Row[];

  const moduleRef = await Test.createTestingModule({
    imports: [
      CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
      BullModule.forRoot({ connection: { host: "127.0.0.1", port: 6379 }, prefix: `test-${randomUUID()}` }),
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
      CoreAuthModule.forRoot({
        secret: "test-secret-at-least-32-characters-long-0",
        baseUrl: "http://127.0.0.1:0",
        trustedOrigins: ["http://127.0.0.1:0"],
        adminOrigin: TEST_ADMIN_ORIGIN,
        googleClientId: "test-google-client-id",
        googleClientSecret: "test-google-client-secret",
        resendApiKey: "re_test_dummy_key_never_sent",
        allowPasswordSignUp: true,
        devSignInCodes: true,
        contactEmail: options.contactEmail,
      }),
      ...(options.imports ?? []),
    ],
    controllers: options.controllers,
    providers: [
      SessionGuard,
      AdminGuard,
      ...(options.providers ?? []),
      { provide: APP_PIPE, useClass: ZodValidationPipe },
      { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
      { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    ],
  })
    .overrideProvider(NotificationsService)
    .useValue({ sendEmail: async () => undefined })
    .overrideProvider(StorageService)
    .useValue(storage)
    .compile();

  const app = moduleRef.createNestApplication({ bodyParser: false });
  const authInstance = app.get(AUTH_INSTANCE);
  const expressApp = app.getHttpAdapter().getInstance() as Express;
  expressApp.all("/api/auth/*splat", toNodeHandler(authInstance));
  expressApp.use(express.json());
  app.setGlobalPrefix("v1", { exclude: [{ path: "api/auth/*path", method: RequestMethod.ALL }] });
  await app.init();
  const baseUrl = await listenOnLoopback(app);
  database = app.get<Database>(DATABASE);
  const seeded: string[] = [];

  const authPost = (path: string, body: unknown, init: { cookie?: string; ip?: string } = {}) =>
    fetch(`${baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-forwarded-for": init.ip ?? freshIp(),
        ...(init.cookie ? { cookie: init.cookie } : {}),
      },
      body: JSON.stringify(body),
    });

  async function signUp(label: string, domain: string): Promise<TestAccount> {
    const email = `${label}-${randomUUID().slice(0, 8)}@${domain}`;
    const response = await authPost("/sign-up/email", { email, password: PASSWORD, name: label });
    if (response.status !== 200) {
      throw new Error(`sign-up ${email}: ${response.status} ${await response.text()}`);
    }
    const { user } = (await response.json()) as { user: { id: string } };
    seeded.push(user.id);
    return { userId: user.id, email, cookie: sessionCookie(response) };
  }

  return {
    app,
    baseUrl,
    storage,
    sql,
    authPost,
    call: (path, cookie, init = {}) =>
      fetch(`${baseUrl}/v1${path}`, {
        method: init.method ?? "GET",
        headers: { cookie, ...(init.body === undefined ? {} : { "content-type": "application/json" }) },
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
      }),
    createAdmin: async (label) => {
      const account = await signUp(label, "example.com");
      const context = await authInstance.$context;
      await context.internalAdapter.updateUser(account.userId, { role: "admin" });
      const signIn = await authPost("/sign-in/email", { email: account.email, password: PASSWORD });
      const cookie = sessionCookie(signIn);
      const enable = await authPost("/two-factor/enable", { password: PASSWORD }, { cookie });
      const { totpURI } = (await enable.json()) as { totpURI: string };
      const secret = new URL(totpURI).searchParams.get("secret")!;
      const verify = await authPost("/two-factor/verify-totp", { code: await computeTotpCode(secret) }, { cookie });
      return { ...account, cookie: sessionCookie(verify) };
    },
    createAthlete: async (label, profile = {}) => {
      const account = await signUp(label, "stravaclone.test");
      await sql(
        "insert into users.user_profile (user_id, first_name, last_name, bio) values ($1, $2, $3, $4)",
        [account.userId, profile.firstName ?? label, profile.lastName ?? "Testeur", profile.bio ?? null],
      );
      return account;
    },
    close: async () => {
      if (seeded.length > 0) {
        await sql('delete from "user" where id = any($1)', [seeded]);
      }
      await app.close();
    },
  };
}
