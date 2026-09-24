import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { Logger } from "nestjs-pino";
import { WorkerModule } from "./worker.module.js";

/**
 * `apps/worker` entry point (ADR-011): a standalone Nest application
 * context, no HTTP listener. `enableShutdownHooks()` lets the process
 * finish in-progress jobs before exiting (ADR-011 §7, ADR-018 §6:
 * `stop_grace_period` 120s).
 */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.createApplicationContext(WorkerModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));
  app.enableShutdownHooks();

  const shutdown = async (): Promise<void> => {
    await app.close();
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown());
  process.on("SIGINT", () => void shutdown());
}

bootstrap().catch((error: unknown) => {
  console.error("Failed to start the worker app", error);
  process.exit(1);
});
