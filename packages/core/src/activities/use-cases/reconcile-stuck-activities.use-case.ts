import { Injectable, NotImplementedException } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import {
  ACTIVITIES_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
  processActivityJobId,
  type ProcessActivityJob,
} from "@repo/contracts";
import { ActivityRepository } from "../repositories/activity.repository.js";

/**
 * Reconciliation (ADR-019 §7): re-enqueues activities stuck `processing`
 * for more than 15 minutes without an active job, every 10 minutes.
 * `apps/worker` schedules this use case (no scheduler dependency in
 * `packages/core`, ADR-021 §6: modules stay framework-thin).
 */
@Injectable()
export class ReconcileStuckActivitiesUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    @InjectQueue(ACTIVITIES_QUEUE_NAME) private readonly queue: Queue<ProcessActivityJob>,
  ) {}

  async execute(): Promise<number> {
    throw new NotImplementedException();
  }
}
