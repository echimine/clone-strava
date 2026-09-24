import { Injectable, NotImplementedException } from "@nestjs/common";
import type { CreateActivityRequest } from "@repo/contracts";
import { ActivityRepository } from "../repositories/activity.repository.js";
import type { ActivityRecord } from "../domain/activity-record.js";

export interface CreateActivityResult {
  activity: ActivityRecord;
  /** Absent once the activity is no longer `pending` (ADR-019 §1). */
  uploadUrl?: { uploadUrl: string; expiresAt: string };
}

/**
 * `POST /v1/activities` (ADR-019 §1): idempotent on `id` (app-generated,
 * ADR-008/ADR-017) — same user + `pending` replays the call with a new
 * upload URL, another user's existing id is a conflict, handled by the
 * caller (`apps/api`) from this use case's result/thrown error.
 */
@Injectable()
export class CreateActivityUseCase {
  constructor(private readonly activities: ActivityRepository) {}

  async execute(_userId: string, _request: CreateActivityRequest): Promise<CreateActivityResult> {
    throw new NotImplementedException();
  }
}
