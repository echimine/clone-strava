import { writeFile } from "node:fs/promises";
import {
  Inject,
  Injectable,
  Logger,
  type OnModuleDestroy,
  type OnModuleInit,
} from "@nestjs/common";
import { REDIS, type Redis } from "@repo/core/infrastructure";

const DEFAULT_HEARTBEAT_FILE = "/tmp/worker-alive";
const HEARTBEAT_INTERVAL_MS = 15_000;

/**
 * Touches a heartbeat file every 15s while Redis is ready (ADR-011
 * "Graceful shutdown", ADR-018 §6). The worker has no HTTP server to expose
 * `/health` on, so the container healthcheck reads this file's mtime
 * instead. Path from `WORKER_HEARTBEAT_FILE`, default `/tmp/worker-alive`.
 */
@Injectable()
export class HeartbeatService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(HeartbeatService.name);
  private readonly filePath = process.env.WORKER_HEARTBEAT_FILE ?? DEFAULT_HEARTBEAT_FILE;
  private interval: NodeJS.Timeout | undefined;

  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  onModuleInit(): void {
    // Write immediately so a healthcheck right after startup succeeds.
    void this.tick();
    this.interval = setInterval(() => void this.tick(), HEARTBEAT_INTERVAL_MS);
  }

  onModuleDestroy(): void {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  private async tick(): Promise<void> {
    if (this.redis.status !== "ready") {
      return;
    }
    try {
      await writeFile(this.filePath, new Date().toISOString());
    } catch (error) {
      this.logger.warn(`Failed to write heartbeat file: ${String(error)}`);
    }
  }
}
