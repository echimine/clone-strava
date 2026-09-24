import { Module } from "@nestjs/common";
import { BullModule } from "@nestjs/bullmq";
import Redis from "ioredis";
import { ConfigModule } from "../config/config.module.js";
import { CONFIG, type WorkerEnv } from "../config/env.js";

/**
 * Shared BullMQ connection for every queue (ADR-011). A dedicated `ioredis`
 * instance, separate from `@repo/core/infrastructure`'s `REDIS`: BullMQ
 * workers issue blocking commands and manage their own connection
 * lifecycle, so this connection is never reused for anything else.
 */
@Module({
  imports: [
    ConfigModule,
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [CONFIG],
      useFactory: (config: WorkerEnv) => ({
        connection: new Redis(config.REDIS_URL, { maxRetriesPerRequest: null }),
      }),
    }),
  ],
  exports: [BullModule],
})
export class AppBullModule {}
