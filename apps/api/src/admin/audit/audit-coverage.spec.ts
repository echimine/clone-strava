import { Controller, Get, Module, Post, RequestMethod, type Type } from "@nestjs/common";
import { METHOD_METADATA, PATH_METADATA } from "@nestjs/common/constants";
import { ModulesContainer } from "@nestjs/core";
import { Test } from "@nestjs/testing";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AuditModule } from "@repo/core/audit";
import { CoreInfrastructureModule } from "@repo/core/infrastructure";
import { ensureTestDatabaseMigrated, TEST_DATABASE_URL, TEST_REDIS_URL } from "../../auth/test-auth-app.js";
import { AUDITED_METADATA } from "./audit-metadata.js";
import { Audited } from "./audited.decorator.js";

/**
 * The non-`GET` routes under `/v1/admin` without `@Audited` (ADR-038 §3: every admin write is
 * recorded), as `METHOD path`, across every controller the app registers.
 */
function unauditedAdminWrites(modules: ModulesContainer): string[] {
  const controllers = new Set<Type>();
  for (const module of modules.values()) {
    for (const wrapper of module.controllers.values()) {
      if (wrapper.metatype) {
        controllers.add(wrapper.metatype as Type);
      }
    }
  }
  const missing: string[] = [];
  for (const controller of controllers) {
    const basePaths = asArray(Reflect.getMetadata(PATH_METADATA, controller) as string | string[] | undefined);
    for (const name of Object.getOwnPropertyNames(controller.prototype)) {
      const handler = (controller.prototype as Record<string, unknown>)[name];
      if (name === "constructor" || typeof handler !== "function") continue;
      const method = Reflect.getMetadata(METHOD_METADATA, handler) as RequestMethod | undefined;
      if (method === undefined || method === RequestMethod.GET) continue;
      const routePaths = asArray(Reflect.getMetadata(PATH_METADATA, handler) as string | string[] | undefined);
      for (const base of basePaths) {
        for (const route of routePaths) {
          const path = [base, route].map(trimSlashes).filter(Boolean).join("/");
          if ((path === "admin" || path.startsWith("admin/")) && !Reflect.getMetadata(AUDITED_METADATA, handler)) {
            missing.push(`${RequestMethod[method]} /v1/${path}`);
          }
        }
      }
    }
  }
  return missing.sort();
}

function asArray(paths: string | string[] | undefined): string[] {
  return paths === undefined ? [""] : Array.isArray(paths) ? paths : [paths];
}

function trimSlashes(path: string): string {
  return path.replace(/^\/+|\/+$/g, "");
}

@Controller("admin/coverage-probe")
class CoverageProbeController {
  @Get()
  read(): void {}

  @Post(":id/audited")
  @Audited("user.sign_out", { reason: "required" })
  audited(): void {}

  @Post(":id/forgotten")
  forgotten(): void {}
}

@Controller("activities")
class AppRouteController {
  @Post()
  create(): void {}
}

@Module({ imports: [AuditModule], controllers: [CoverageProbeController, AppRouteController] })
class ProbeModule {}

describe("every admin write is @Audited (ADR-038 §3, architecture)", () => {
  it("names an undecorated admin write, and nothing else", async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [
        CoreInfrastructureModule.forRoot({ databaseUrl: TEST_DATABASE_URL, redisUrl: TEST_REDIS_URL }),
        ProbeModule,
      ],
    }).compile();

    expect(unauditedAdminWrites(moduleRef.get(ModulesContainer))).toEqual([
      "POST /v1/admin/coverage-probe/:id/forgotten",
    ]);
    await moduleRef.close();
  });

  describe("in the real AppModule", () => {
    let modules: ModulesContainer;
    let close: () => Promise<void>;

    beforeAll(async () => {
      await ensureTestDatabaseMigrated();
      // `AppModule` reads its environment when it is loaded: never the developer's own `.env`.
      Object.assign(process.env, {
        NODE_ENV: "test",
        DATABASE_URL: TEST_DATABASE_URL,
        REDIS_URL: TEST_REDIS_URL,
        LOG_LEVEL: "error",
        BETTER_AUTH_SECRET: "test-secret-at-least-32-characters-long-0",
        BETTER_AUTH_URL: "http://127.0.0.1:0",
        REALTIME_TOKEN_SECRET: "test-realtime-secret",
        S3_ENDPOINT: "https://bucket.test",
        S3_REGION: "test",
        S3_BUCKET: "test",
        S3_ACCESS_KEY_ID: "test",
        S3_SECRET_ACCESS_KEY: "test",
        REVENUECAT_WEBHOOK_SECRET: "test",
        RESEND_API_KEY: "re_test_dummy_key_never_sent",
        RESEND_WEBHOOK_SECRET: "test",
        GOOGLE_CLIENT_ID: "test",
        GOOGLE_CLIENT_SECRET: "test",
      });
      delete process.env.POSTHOG_API_KEY;
      const { AppModule } = await import("../../app.module.js");
      const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
      modules = moduleRef.get(ModulesContainer);
      close = () => moduleRef.close();
    }, 30_000);

    afterAll(async () => {
      await close?.();
    });

    it("has no admin write without @Audited", () => {
      expect(unauditedAdminWrites(modules)).toEqual([]);
    });
  });
});
