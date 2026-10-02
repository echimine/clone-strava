import { Injectable } from "@nestjs/common";
import type {
  ActivityImport,
  CreateActivityImportRequest,
  CreateActivityRequest,
  ImportActivityJob,
  ListActivityImportsQuery,
  ListActivityImportsResponse,
  ProcessActivityJob,
  UploadUrlResponse,
} from "@repo/contracts";
import { CreateActivityUseCase, type CreateActivityResult } from "./use-cases/create-activity.use-case.js";
import { RequestUploadUrlUseCase } from "./use-cases/request-upload-url.use-case.js";
import { CompleteActivityUseCase } from "./use-cases/complete-activity.use-case.js";
import { ProcessActivityUseCase } from "./use-cases/process-activity.use-case.js";
import { ReconcileStuckActivitiesUseCase } from "./use-cases/reconcile-stuck-activities.use-case.js";
import { GetActivitiesUseCase } from "./use-cases/get-activities.use-case.js";
import {
  CreateActivityImportUseCase,
  type CreateActivityImportResult,
} from "./use-cases/create-activity-import.use-case.js";
import { RequestImportUploadUrlUseCase } from "./use-cases/request-import-upload-url.use-case.js";
import { CompleteActivityImportUseCase } from "./use-cases/complete-activity-import.use-case.js";
import { GetActivityImportsUseCase } from "./use-cases/get-activity-imports.use-case.js";
import {
  ImportActivityFromFileUseCase,
  type ImportActivityResult,
} from "./use-cases/import-activity-from-file.use-case.js";
import { ReprocessActivityImportUseCase } from "./use-cases/reprocess-activity-import.use-case.js";
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
    private readonly createActivityImportUseCase: CreateActivityImportUseCase,
    private readonly requestImportUploadUrlUseCase: RequestImportUploadUrlUseCase,
    private readonly completeActivityImportUseCase: CompleteActivityImportUseCase,
    private readonly getActivityImportsUseCase: GetActivityImportsUseCase,
    private readonly importActivityFromFileUseCase: ImportActivityFromFileUseCase,
    private readonly reprocessActivityImportUseCase: ReprocessActivityImportUseCase,
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
  process(job: ProcessActivityJob): Promise<void> {
    return this.processActivityUseCase.execute(job);
  }

  /** Last technical attempt of `process-activity` failed (ADR-019 §6). */
  markProcessingFailed(job: ProcessActivityJob): Promise<void> {
    return this.processActivityUseCase.markTechnicalFailure(job);
  }

  /** Called by `apps/worker`'s reconciliation schedule (ADR-019 §7). */
  reconcileStuck(): Promise<number> {
    return this.reconcileStuckActivitiesUseCase.execute();
  }

  /** Batch read (ADR-021 §2 rule 6): used by `engagement`, `segments` and list screens. */
  getMany(ids: string[]): Promise<ActivityRecord[]> {
    return this.getActivitiesUseCase.execute(ids);
  }

  // --- File import (ADR-028) ---

  createImport(userId: string, request: CreateActivityImportRequest): Promise<CreateActivityImportResult> {
    return this.createActivityImportUseCase.execute(userId, request);
  }

  requestImportUploadUrl(userId: string, importId: string): Promise<UploadUrlResponse> {
    return this.requestImportUploadUrlUseCase.execute(userId, importId);
  }

  completeImport(userId: string, importId: string, requestId?: string): Promise<ActivityImport> {
    return this.completeActivityImportUseCase.execute(userId, importId, requestId);
  }

  getImport(userId: string, importId: string): Promise<ActivityImport> {
    return this.getActivityImportsUseCase.getOne(userId, importId);
  }

  listImports(userId: string, query: ListActivityImportsQuery): Promise<ListActivityImportsResponse> {
    return this.getActivityImportsUseCase.list(userId, query);
  }

  /** Called by `apps/worker`'s `import-activity` processor (ADR-028 §4). */
  importFromFile(job: ImportActivityJob): Promise<ImportActivityResult> {
    return this.importActivityFromFileUseCase.execute(job);
  }

  /** Last technical attempt of `import-activity` failed (ADR-028 §7). */
  markImportFailed(job: ImportActivityJob): Promise<void> {
    return this.importActivityFromFileUseCase.markTechnicalFailure(job);
  }

  /** Backoffice reprocessing of a failed import (ADR-028 §7). */
  reprocessImport(importId: string, requestId?: string): Promise<ActivityImport> {
    return this.reprocessActivityImportUseCase.execute(importId, requestId);
  }
}
