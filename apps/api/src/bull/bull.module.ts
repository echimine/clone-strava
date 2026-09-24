import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { REDIS, type Redis } from "@repo/core/infrastructure";

/**
 * Producer-only BullMQ connection (ADR-009 §"api stack": "the API never
 * runs a job, it only enqueues them"). No `@Processor` lives in this app.
 * Shares the `REDIS` connection from `CoreInfrastructureModule`: safe here
 * because a producer-only `Queue` never issues the blocking commands a
 * BullMQ `Worker` does.
 */
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [REDIS],
      useFactory: (redis: Redis) => ({ connection: redis }),
    }),
  ],
  exports: [BullModule],
})
export class AppBullModule {}
