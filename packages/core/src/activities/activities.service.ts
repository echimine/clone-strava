import { Injectable } from "@nestjs/common";
import type { CreateActivityRequest } from "@repo/contracts";
import { CreateActivityUseCase, type CreateActivityResult } from "./use-cases/create-activity.use-case.js";
import { RequestUploadUrlUseCase } from "./use-cases/request-upload-url.use-case.js";
import { CompleteActivityUseCase } from "./use-cases/complete-activity.use-case.js";
import { ProcessActivityUseCase } from "./use-cases/process-activity.use-case.js";
import { ReconcileStuckActivitiesUseCase } from "./use-cases/reconcile-stuck-activities.use-case.js";
import { GetActivitiesUseCase } from "./use-cases/get-activities.use-case.js";
import type { ActivityRecord } from "./domain/activity-record.js";

/**
 * Public facade of the `activities` module (ADR-021 §1: layer 2, may
 * depend on `sports`, `users`, `social`). The largest module (upload,
 * processing, feed).
 */
@Injectable()
export class ActivitiesService {
  constructor(
    private readonly createActivityUseCase: CreateActivityUseCase,
    private readonly requestUploadUrlUseCase: RequestUploadUrlUseCase,
    private readonly completeActivityUseCase: CompleteActivityUseCase,
    private readonly processActivityUseCase: ProcessActivityUseCase,
    private readonly reconcileStuckActivitiesUseCase: ReconcileStuckActivitiesUseCase,
    private readonly getActivitiesUseCase: GetActivitiesUseCase,
  ) {}

  create(userId: string, request: CreateActivityRequest): Promise<CreateActivityResult> {
    return this.createActivityUseCase.execute(userId, request);
  }

  requestUploadUrl(userId: string, activityId: string) {
    return this.requestUploadUrlUseCase.execute(userId, activityId);
  }

  complete(userId: string, activityId: string, requestId?: string): Promise<ActivityRecord> {
    return this.completeActivityUseCase.execute(userId, activityId, requestId);
  }

  /** Called by `apps/worker`'s `process-activity` processor (ADR-011 §1). */
  process(job: Parameters<ProcessActivityUseCase["execute"]>[0]): Promise<void> {
    return this.processActivityUseCase.execute(job);
  }

  /** Called by `apps/worker`'s reconciliation schedule (ADR-019 §7). */
  reconcileStuck(): Promise<number> {
    return this.reconcileStuckActivitiesUseCase.execute();
  }

  /** Batch read (ADR-021 §2 rule 6): used by `engagement`, `segments` and list screens. */
  getMany(ids: string[]): Promise<ActivityRecord[]> {
    return this.getActivitiesUseCase.execute(ids);
  }
}
