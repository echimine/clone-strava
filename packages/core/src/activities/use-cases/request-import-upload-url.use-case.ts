import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { activityImportSourceKey, type UploadUrlResponse } from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { IMPORT_UPLOAD_CONTENT_TYPE } from "./create-activity-import.use-case.js";

/** `POST /v1/activity-imports/:id/upload-url` (ADR-028 §3): renewal while `pending`, otherwise `409`. */
@Injectable()
export class RequestImportUploadUrlUseCase {
  constructor(
    private readonly imports: ActivityImportRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, importId: string): Promise<UploadUrlResponse> {
    const row = await this.imports.findById(importId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Import not found" });
    }
    if (row.status !== "pending") {
      throw new ConflictException({ code: "not_pending", message: "The file was already uploaded" });
    }
    const presigned = await this.storage.presignPut(
      activityImportSourceKey(row.userId, row.id, row.format),
      IMPORT_UPLOAD_CONTENT_TYPE,
    );
    return { uploadUrl: presigned.url, expiresAt: presigned.expiresAt.toISOString() };
  }
}
