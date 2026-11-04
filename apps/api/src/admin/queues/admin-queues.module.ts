import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ADMIN_QUEUE_NAMES } from "@repo/contracts";
import { AdminQueues } from "./admin-queues.js";

/**
 * Every whitelisted queue as a producer (ADR-038 §14), read and driven by {@link AdminQueues}:
 * the Jobs screen and the dashboard's failed jobs count (ADR-038 §15).
 */
@Module({
  imports: [BullModule.registerQueue(...ADMIN_QUEUE_NAMES.map((name) => ({ name })))],
  providers: [AdminQueues],
  exports: [AdminQueues],
})
export class AdminQueuesModule {}
