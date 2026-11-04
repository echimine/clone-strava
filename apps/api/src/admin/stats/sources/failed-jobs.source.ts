import { getQueueToken } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import { ModuleRef } from "@nestjs/core";
import type { Queue } from "bullmq";
import { ADMIN_QUEUE_NAMES } from "@repo/contracts";

/**
 * The queues whose failed jobs the "Jobs en échec" tile adds up (ADR-038 §14, §15): the
 * backoffice's queue whitelist, the one the Jobs screen reads.
 */
export function dashboardQueueNames(): readonly string[] {
  return ADMIN_QUEUE_NAMES;
}

/** Failed jobs, all queues together, for the "À traiter" band (ADR-038 §15). */
@Injectable()
export class FailedJobsSource {
  constructor(private readonly moduleRef: ModuleRef) {}

  async count(): Promise<number> {
    const counts = await Promise.all(
      dashboardQueueNames().map((name) =>
        this.moduleRef.get<Queue>(getQueueToken(name), { strict: false }).getFailedCount(),
      ),
    );
    return counts.reduce((total, failed) => total + failed, 0);
  }
}
