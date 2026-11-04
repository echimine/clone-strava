import { getQueueToken } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import { ModuleRef } from "@nestjs/core";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  AVATARS_QUEUE_NAME,
  IMPORTS_QUEUE_NAME,
  SEGMENTS_QUEUE_NAME,
  SUBSCRIPTIONS_QUEUE_NAME,
} from "@repo/contracts";

/**
 * The queues whose failed jobs the "Jobs en échec" tile adds up (ADR-038 §14, §15).
 *
 * Today's queues, listed by hand: #216 formalises the admin queue whitelist in `contracts` (with
 * `accounts` and `emails`, and `bucket-sweep` moved out of the worker) and makes this return it.
 */
export function dashboardQueueNames(): readonly string[] {
  return [
    ACTIVITIES_QUEUE_NAME,
    IMPORTS_QUEUE_NAME,
    SEGMENTS_QUEUE_NAME,
    SUBSCRIPTIONS_QUEUE_NAME,
    AVATARS_QUEUE_NAME,
    "bucket-sweep",
  ];
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
