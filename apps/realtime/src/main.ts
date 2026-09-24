import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { Logger } from "nestjs-pino";
import { AppModule } from "./app.module.js";
import { CONFIG, type RealtimeEnv } from "./config/env.js";

/**
 * `apps/realtime` entry point (ADR-010). HTTP is only used for `/health`
 * and to receive the `upgrade` event that `GatewayService` hooks into.
 */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));
  // Closes every open connection with 4009 before the process exits (ADR-010 §9, ADR-018 §6).
  app.enableShutdownHooks();

  const config = app.get<RealtimeEnv>(CONFIG);
  await app.listen(config.PORT);
}

bootstrap().catch((error: unknown) => {
  console.error("Failed to start the realtime app", error);
  process.exit(1);
});
