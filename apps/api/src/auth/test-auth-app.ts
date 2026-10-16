import { toNodeHandler } from "better-auth/node";
import express, { type Express } from "express";
import { Redis } from "ioredis";
import { Controller, Get, RequestMethod, UseGuards } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import type { INestApplication } from "@nestjs/common";
import { APP_FILTER } from "@nestjs/core";
import { CoreInfrastructureModule } from "@repo/core/infrastructure";
import { AuthModule as CoreAuthModule, AUTH_INSTANCE } from "@repo/core/auth";
import { NotificationsService } from "@repo/core/notifications";
import { runMigrations } from "@repo/db/migrate";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { AdminGuard } from "./admin.guard.js";
import { SessionGuard } from "./session.guard.js";

/**
 * Stand-in for `AdminModule`'s real `AdminController` (ADR-021 §1 "Not a
 * module: admin"): same `@UseGuards(SessionGuard, AdminGuard)` +
 * `GET /admin` shape, kept local to this test helper instead of importing
 * the real `apps/api/src/admin` module, whose sibling `auth.module.ts`
 * calls `loadConfig()` at import time and would require the full real
 * environment rather than this file's test-only options.
 */
@Controller("admin")
@UseGuards(SessionGuard, AdminGuard)
class TestAdminController {
  @Get()
  ping(): { status: "ok" } {
    return { status: "ok" };
  }
}


/**
 * Local-dev/test-only endpoints (`docker-compose.dev.yml`, ADR-018 §8).
 * Never the real Resend API key: `NotificationsService` is spied on/
 * mocked in every test that boots this app, so `sendAuthEmail` never
 * actually reaches Resend from here.
 */
export const TEST_DATABASE_URL = "postgres://strava:strava@127.0.0.1:5432/strava";
export const TEST_REDIS_URL = "redis://127.0.0.1:6379";
export const TEST_EMAIL_LOGO_URL = "https://admin.test/brand/nervo-wordmark-email.png";

export interface TestAuthApp {
  app: INestApplication;
  expressApp: Express;
  baseUrl: string;
  notificationsService: NotificationsService;
}

/**
 * Boots a minimal Nest app wired the same way `main.ts` wires the real one
 * (ADR-009 §3): Better Auth mounted by hand at `/api/auth/*` via
 * `toNodeHandler`, `bodyParser` re-enabled after that mount, so
 * `POST /api/auth/sign-up/email` / `/sign-in/email` behave exactly as they
 * do in production (rate limiting, cookies, Redis secondary storage all
 * real, not mocked).
 *
 * `NotificationsService.sendAuthEmail` is replaced with a spy (never hits
 * Resend from a test) unless `mockNotifications: false` is passed for the
 * one test that needs a real send.
 */
export async function bootstrapTestAuthApp(
  options: { mockNotifications?: boolean; withAdminRoute?: boolean } = {},
): Promise<TestAuthApp> {
  const { mockNotifications = true, withAdminRoute = false } = options;

  const moduleBuilder = Test.createTestingModule({
    imports: [
      CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
      CoreAuthModule.forRoot({
        secret: "test-secret-at-least-32-characters-long-0",
        baseUrl: "http://127.0.0.1:0",
        trustedOrigins: ["http://127.0.0.1:0"],
        emailLogoUrl: TEST_EMAIL_LOGO_URL,
        googleClientId: "test-google-client-id",
        googleClientSecret: "test-google-client-secret",
        resendApiKey: "re_test_dummy_key_never_sent",
      }),
    ],
    controllers: withAdminRoute ? [TestAdminController] : [],
    // `SessionGuard`/`AdminGuard` are declared directly in this top-level
    // testing module (not a nested `TestAdminModule`) so they can inject
    // `AuthService`/`AUTH_INSTANCE` straight from the sibling
    // `CoreAuthModule.forRoot(...)` import above -- Nest doesn't flatten
    // providers across sibling module imports, so a separate sub-module
    // would need its own explicit `imports`, which isn't possible here
    // since `CoreAuthModule.forRoot(...)`'s *instance* (with this file's
    // test options) only exists on this testing module, not as a
    // reusable, re-importable reference.
    providers: withAdminRoute
      ? [SessionGuard, AdminGuard, { provide: APP_FILTER, useClass: GlobalExceptionFilter }]
      : [],
  });

  if (mockNotifications) {
    moduleBuilder.overrideProvider(NotificationsService).useValue({
      sendAuthEmail: async () => {
        // No-op: assertions read the spy directly (vi.spyOn on this
        // method after module creation) rather than relying on network.
      },
    });
  }

  const moduleRef = await moduleBuilder.compile();
  const app = moduleRef.createNestApplication({ bodyParser: false });

  const authInstance = app.get(AUTH_INSTANCE);
  const expressApp = app.getHttpAdapter().getInstance() as Express;
  expressApp.all("/api/auth/*splat", toNodeHandler(authInstance));
  expressApp.use(express.json());

  if (withAdminRoute) {
    // Mirrors `main.ts`'s `setGlobalPrefix("v1", ...)`: `TestAdminController`
    // ends up reachable at `/v1/admin`, same as the real `AdminController`.
    app.setGlobalPrefix("v1", { exclude: [{ path: "api/auth/*path", method: RequestMethod.ALL }] });
  }

  await app.init();
  await app.listen(0);
  const server = app.getHttpServer();
  const address = server.address();
  const port = typeof address === "object" && address !== null ? address.port : 0;
  const baseUrl = `http://127.0.0.1:${port}`;

  const notificationsService = app.get(NotificationsService);

  return { app, expressApp, baseUrl, notificationsService };
}

/** Applies every pending migration once, before any test suite boots the app. */
export async function ensureTestDatabaseMigrated(): Promise<void> {
  await runMigrations(TEST_DATABASE_URL);
}

// Better Auth's `customRules` (create-auth-instance.ts) key the rate
// limiter by `${ip}|${path}` -- confirmed by inspecting the actual keys
// written to the dev Redis during manual testing -- so every spec file in
// this suite shares the same budget (all requests come from this process,
// same loopback IP). Every spec that hits `/api/auth/sign-up/email` or
// `/sign-in/email` outside its own dedicated rate-limiting test must clear
// these first, or an earlier spec file's (or an earlier run's) leftover
// count can make an unrelated assertion fail with 429.
const RATE_LIMIT_KEYS = ["127.0.0.1|/sign-up/email", "127.0.0.1|/sign-in/email"];

export async function clearRateLimitCounters(): Promise<void> {
  const redis = new Redis(TEST_REDIS_URL);
  await redis.del(...RATE_LIMIT_KEYS);
  await redis.quit();
}
