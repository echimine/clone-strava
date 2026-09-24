import "reflect-metadata";
import { toNodeHandler } from "better-auth/node";
import express from "express";
import { RequestMethod } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import { cleanupOpenApiDoc } from "nestjs-zod";
import { Logger } from "nestjs-pino";
import { AUTH_INSTANCE } from "@repo/core/auth";
import { runMigrations } from "@repo/db/migrate";
import { AppModule } from "./app.module.js";
import { loadConfig } from "./config/env.js";

/**
 * `apps/api` entry point (ADR-009, ADR-018 §4).
 *
 * Migrations run before the Nest app is even created: the api stays at a
 * single instance (ADR-018 §4), so running them here -- guarded by
 * `RUN_MIGRATIONS !== 'false'` -- is safe and keeps `db:migrate` out of the
 * deployment script.
 */
async function bootstrap(): Promise<void> {
  const config = loadConfig();

  if (process.env.RUN_MIGRATIONS !== "false") {
    await runMigrations(config.DATABASE_URL);
  }

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
    // Required by Better Auth (ADR-009 §3): re-enabled below, after the
    // handler is mounted, for the rest of the app.
    bodyParser: false,
  });
  app.useLogger(app.get(Logger));
  // Otherwise `@nestjs/throttler` (and any future rate limiting) sees
  // Traefik's IP for every client (ADR-018, risks).
  app.set("trust proxy", 1);
  app.enableShutdownHooks();

  const authInstance = app.get(AUTH_INSTANCE);
  const expressApp = app.getHttpAdapter().getInstance();
  expressApp.all("/api/auth/*splat", toNodeHandler(authInstance));
  app.use(express.json());

  // Versioned routes (ADR-009 §8), excluding `/health` (ADR-018 §6, public,
  // outside rate limiting and authentication) and the Better Auth mount.
  app.setGlobalPrefix("v1", {
    exclude: [
      { path: "health", method: RequestMethod.GET },
      { path: "api/auth/*path", method: RequestMethod.ALL },
    ],
  });

  // OpenAPI, generated from the same Zod schemas used to validate requests
  // (ADR-009 §"api stack" "Documentation"): later generates the Swift
  // models (ADR-005). `SwaggerModule.setup` registers its routes directly
  // on the adapter, so they sit outside both the `/v1` prefix (no
  // `useGlobalPrefix`) and the global `ThrottlerGuard` (which only wraps
  // Nest-routed controllers).
  const openApiConfig = new DocumentBuilder()
    .setTitle("Clone Strava API")
    .setDescription("REST API for the mobile app and the backoffice (ADR-009).")
    .setVersion("1")
    .build();
  const openApiDocument = cleanupOpenApiDoc(SwaggerModule.createDocument(app, openApiConfig));
  SwaggerModule.setup("docs", app, openApiDocument, { jsonDocumentUrl: "docs/openapi.json" });

  await app.listen(config.PORT);
}

bootstrap().catch((error: unknown) => {
  console.error("Failed to start the api app", error);
  process.exit(1);
});
