import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import type { ActivityImport } from "@repo/contracts";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { toActivityImport } from "../domain/activity-import-record.js";
import { ImportJobEnqueuer } from "../services/import-job-enqueuer.js";

/** `POST /v1/admin/activity-imports/:id/reprocess` (ADR-028 §7): `failed` -> `processing`, re-enqueue. */
@Injectable()
export class ReprocessActivityImportUseCase {
  constructor(
    private readonly imports: ActivityImportRepository,
    private readonly enqueuer: ImportJobEnqueuer,
  ) {}

  async execute(importId: string, requestId?: string): Promise<ActivityImport> {
    const row = await this.imports.findById(importId);
    if (!row) {
      throw new NotFoundException({ code: "not_found", message: "Import not found" });
    }
    if (!(await this.imports.resetFailedToProcessing(row.id))) {
      throw new ConflictException({ code: "not_failed", message: "Only failed imports can be reprocessed" });
    }
    await this.enqueuer.enqueue({ importId: row.id, userId: row.userId, requestId });
    return toActivityImport((await this.imports.findById(row.id)) ?? row);
  }
}
