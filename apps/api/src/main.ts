import "reflect-metadata";
import { toNodeHandler } from "better-auth/node";
import express from "express";
import { NestFactory } from "@nestjs/core";
import type { NestExpressApplication } from "@nestjs/platform-express";
import { SwaggerModule } from "@nestjs/swagger";
import { Logger } from "nestjs-pino";
import { AUTH_INSTANCE } from "@repo/core/auth";
import { runMigrations } from "@repo/db/migrate";
import { AppModule } from "./app.module.js";
import { loadConfig } from "./config/env.js";
import { applyGlobalPrefix, createOpenApiDocument } from "./openapi/document.js";

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
  // `verify` always receives the pre-parse buffer, for every route; teeing
  // it onto `req.rawBody` for the Resend webhook alone gives
  // `ResendWebhookController` byte-exact bytes for its Svix HMAC check
  // (ADR-023) without a second raw-body-only middleware/route.
  app.use(
    express.json({
      // `verify` types `req` as the bare `http.IncomingMessage`
      // (body-parser has no express dependency); `originalUrl`/`rawBody`
      // are express-only, hence the single cast for both reads/writes.
      verify: (req, _res, buf) => {
        const request = req as express.Request & { rawBody?: Buffer };
        if (request.originalUrl === "/v1/webhooks/resend") {
          request.rawBody = buf;
        }
      },
    }),
  );

  applyGlobalPrefix(app);

  // `SwaggerModule.setup` registers its routes directly on the adapter, so
  // they sit outside both the `/v1` prefix (no `useGlobalPrefix`) and the
  // global `ThrottlerGuard` (which only wraps Nest-routed controllers).
  SwaggerModule.setup("docs", app, createOpenApiDocument(app), { jsonDocumentUrl: "docs/openapi.json" });

  await app.listen(config.PORT);
}

bootstrap().catch((error: unknown) => {
  console.error("Failed to start the api app", error);
  process.exit(1);
});
