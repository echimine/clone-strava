import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import type { UploadUrlResponse } from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { presignTraceUpload } from "./create-activity.use-case.js";

/** `POST /v1/activities/:id/upload-url` (ADR-019 §2): renewal while `pending`, otherwise `409`. */
@Injectable()
export class RequestUploadUrlUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, activityId: string): Promise<UploadUrlResponse> {
    const row = await this.activities.findById(activityId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }
    if (row.processingStatus !== "pending") {
      throw new ConflictException({ code: "not_pending", message: "The trace was already uploaded" });
    }
    return presignTraceUpload(this.storage, row);
  }
}
