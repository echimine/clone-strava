import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { ADMIN_QUEUE_NAMES } from "@repo/contracts";
import { JOB_RETENTION } from "@repo/core/infrastructure";
import { AppModule } from "../app.module.js";
import { AdminQueues } from "../admin/queues/admin-queues.js";

/**
 * One-off cleanup (ADR-038 §14, amends ADR-011): before the bounded retention, the
 * `reconcile-activities` runs (every 10 minutes, no `removeOnComplete` on the scheduler's
 * template) and the `match-segments` jobs were kept in Redis forever. This removes, on every
 * whitelisted queue, the completed jobs older than 7 days and the failed ones older than
 * 30 days, the ages new jobs now get; replayable without side effect. Run once after deploying,
 * in the `api` container: `node dist/scripts/clean-queues.js` (`pnpm --filter api clean:queues`
 * locally). The backoffice itself never removes a job.
 */
async function cleanQueues(): Promise<void> {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ["error", "warn"] });
  try {
    const queues = app.get(AdminQueues);
    for (const name of ADMIN_QUEUE_NAMES) {
      const queue = queues.queue(name);
      const completed = await queue.clean(JOB_RETENTION.removeOnComplete.age * 1000, 0, "completed");
      const failed = await queue.clean(JOB_RETENTION.removeOnFail.age * 1000, 0, "failed");
      console.log(`${name}: ${completed.length} completed and ${failed.length} failed job(s) removed`);
    }
  } finally {
    await app.close();
  }
}

cleanQueues().catch((error: unknown) => {
  console.error("Queue cleanup failed", error);
  process.exit(1);
});
