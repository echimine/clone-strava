import type { INestApplication } from "@nestjs/common";
import { APP_FILTER, APP_INTERCEPTOR, APP_PIPE } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import jwt from "jsonwebtoken";
import { ZodSerializerInterceptor, ZodValidationPipe } from "nestjs-zod";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuthService } from "@repo/core/auth";
import { SessionGuard } from "../auth/session.guard.js";
import { GlobalExceptionFilter } from "../common/global-exception.filter.js";
import { CONFIG } from "../config/env.js";
import { listenOnLoopback } from "../testing/listen-on-loopback.js";
import { LiveParticipantTokenController, participantName } from "./live-participant-token.controller.js";

const SECRET = "live-spec-secret-at-least-32-characters";
const USER_ID = "user-1042";

/** The session is `x-test-user` / `x-test-name`. */
async function startApp(config: Record<string, unknown>): Promise<{ app: INestApplication; baseUrl: string }> {
  const moduleRef = await Test.createTestingModule({
    controllers: [LiveParticipantTokenController],
    providers: [
      SessionGuard,
      { provide: CONFIG, useValue: config },
      {
        provide: AuthService,
        useValue: {
          getSession: async (headers: Headers) => {
            const userId = headers.get("x-test-user");
            return userId
              ? { userId, email: "a@test.local", name: headers.get("x-test-name") ?? "", role: "user", twoFactorEnabled: false }
              : null;
          },
        },
      },
      { provide: APP_PIPE, useClass: ZodValidationPipe },
      { provide: APP_INTERCEPTOR, useClass: ZodSerializerInterceptor },
      { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    ],
  }).compile();
  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix("v1");
  return { app, baseUrl: await listenOnLoopback(app) };
}

function requestToken(baseUrl: string, headers: Record<string, string>) {
  return fetch(`${baseUrl}/v1/live/participant-token`, { method: "POST", headers });
}

describe("POST /v1/live/participant-token", () => {
  let configured: { app: INestApplication; baseUrl: string };
  let unconfigured: { app: INestApplication; baseUrl: string };

  beforeAll(async () => {
    configured = await startApp({ LIVE_APP_ID: "strava", LIVE_TOKEN_SECRET: SECRET });
    unconfigured = await startApp({ LIVE_APP_ID: "strava" });
  });

  afterAll(async () => {
    await configured.app.close();
    await unconfigured.app.close();
  });

  it("signs a 5 min HS256 Participant token for the signed-in user", async () => {
    const response = await requestToken(configured.baseUrl, { "x-test-user": USER_ID, "x-test-name": "Léa Martin" });

    expect(response.status).toBe(200);
    const { token } = (await response.json()) as { token: string };
    const claims = jwt.verify(token, SECRET, { algorithms: ["HS256"], issuer: "strava" }) as jwt.JwtPayload;
    expect(claims).toMatchObject({ sub: USER_ID, name: "Léa Martin" });
    expect(claims.exp! - claims.iat!).toBe(300);
  });

  it("answers 503 live_not_configured without a secret", async () => {
    const response = await requestToken(unconfigured.baseUrl, { "x-test-user": USER_ID, "x-test-name": "Léa" });

    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("live_not_configured");
  });

  it("answers 401 without a session", async () => {
    expect((await requestToken(configured.baseUrl, {})).status).toBe(401);
  });
});

describe("participantName", () => {
  it("keeps at most 30 visible characters without cutting a composed emoji", () => {
    const family = "👨‍👩‍👧";
    const name = `${"a".repeat(29)}${family}${family}`;
    expect(participantName(name)).toBe(`${"a".repeat(29)}${family}`);
  });

  it("trims, and falls back to « Athlète » when empty", () => {
    expect(participantName("  Léa  ")).toBe("Léa");
    expect(participantName("   ")).toBe("Athlète");
  });
});
