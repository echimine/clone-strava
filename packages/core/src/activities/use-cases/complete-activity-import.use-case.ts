import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import {
  ACTIVITY_IMPORT_MAX_FILE_BYTES,
  activityImportSourceKey,
  type ActivityImport,
} from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { toActivityImport } from "../domain/activity-import-record.js";
import { ImportJobEnqueuer } from "../services/import-job-enqueuer.js";

/**
 * `POST /v1/activity-imports/:id/complete` (ADR-028 §3): `HEAD` the source
 * file, `pending` -> `processing`, enqueue `import-activity` right after
 * the commit (ADR-021 §3 job rules). A lost enqueue is caught by the
 * reconciliation sweep (ADR-028 §8).
 */
@Injectable()
export class CompleteActivityImportUseCase {
  constructor(
    private readonly imports: ActivityImportRepository,
    private readonly storage: StorageService,
    private readonly enqueuer: ImportJobEnqueuer,
  ) {}

  async execute(userId: string, importId: string, requestId?: string): Promise<ActivityImport> {
    const row = await this.imports.findById(importId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Import not found" });
    }
    if (row.status === "failed") {
      throw new ConflictException({ code: "import_failed", message: "This import has failed" });
    }
    if (row.status !== "pending") {
      // Replayed call: already processing or finished, nothing to enqueue.
      return toActivityImport(row);
    }

    const head = await this.storage.head(activityImportSourceKey(row.userId, row.id, row.format));
    if (!head) {
      throw new ConflictException({ code: "file_missing", message: "The file has not been uploaded" });
    }
    if (head.sizeBytes > ACTIVITY_IMPORT_MAX_FILE_BYTES) {
      throw new ConflictException({ code: "file_too_large", message: "The file is too large" });
    }

    if (await this.imports.markProcessingIfPending(row.id)) {
      await this.enqueuer.enqueue({ importId: row.id, userId, requestId });
    }
    const updated = await this.imports.findById(row.id);
    return toActivityImport(updated ?? row);
  }
}
