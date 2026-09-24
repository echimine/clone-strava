import { Injectable, NotImplementedException } from "@nestjs/common";
import { ActivityRepository } from "../repositories/activity.repository.js";

/** `POST /v1/activities/:id/upload-url` (ADR-019 §2): renewal, only while `pending`. */
@Injectable()
export class RequestUploadUrlUseCase {
  constructor(private readonly activities: ActivityRepository) {}

  async execute(
    _userId: string,
    _activityId: string,
  ): Promise<{ uploadUrl: string; expiresAt: string }> {
    throw new NotImplementedException();
  }
}
