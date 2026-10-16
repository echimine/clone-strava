import { ConflictException, Injectable, UnprocessableEntityException } from "@nestjs/common";
import {
  ACTIVITY_TRACE_CONTENT_TYPE,
  activityTraceKey,
  type CreateActivityRequest,
  type UploadUrlResponse,
} from "@repo/contracts";
import { SportsService } from "../../sports/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { toActivityRecord, type ActivityRecord } from "../domain/activity-record.js";

export interface CreateActivityResult {
  activity: ActivityRecord;
  /** Absent once the activity is no longer `pending` (ADR-019 §1). */
  uploadUrl?: UploadUrlResponse;
  /** `true` -> `201`, `false` -> `200` (replayed call). */
  created: boolean;
}

/**
 * `POST /v1/activities` (ADR-019 §1): idempotent on `id` (app-generated,
 * ADR-008/ADR-017). The provisional values of the request are never
 * stored: the worker recomputes everything from the trace.
 */
@Injectable()
export class CreateActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly sports: SportsService,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, request: CreateActivityRequest): Promise<CreateActivityResult> {
    const existing = await this.activities.findById(request.id);
    if (existing) {
      return this.replay(userId, existing);
    }
    await this.validate(request);

    const inserted = await this.activities.insertIfAbsent({
      id: request.id,
      userId,
      sportTypeCode: request.sportTypeCode,
      title: request.title,
      description: request.description,
      startedAt: new Date(request.startedAt),
      endedAt: new Date(request.endedAt),
      visibility: request.visibility,
      isManual: request.isManual,
      source: "recorded",
    });
    const row = await this.activities.findById(request.id);
    if (!row) {
      throw new Error(`Activity ${request.id} vanished right after insert`);
    }
    if (!inserted) {
      // Lost a race with a concurrent replay of the same `POST`.
      return this.replay(userId, row);
    }
    return {
      activity: toActivityRecord(row),
      uploadUrl: await presignTraceUpload(this.storage, row),
      created: true,
    };
  }

  /**
   * ADR-019 §1 `422`: active sport, duration at least the sport's minimum (`endedAt > startedAt`
   * is in the contract); the provisional moving time and distance, when sent, at least the
   * sport's minimums too (ADR-031 §11).
   */
  private async validate(request: CreateActivityRequest): Promise<void> {
    const sport = await this.sports.findByCode(request.sportTypeCode);
    if (!sport || !sport.isActive) {
      throw invalid("sportTypeCode", "Unknown or inactive sport type");
    }
    const durationS = (Date.parse(request.endedAt) - Date.parse(request.startedAt)) / 1000;
    if (durationS < sport.minDurationS) {
      throw invalid("endedAt", `The activity must last at least ${sport.minDurationS} s`);
    }
    if (request.movingTimeS !== undefined && request.movingTimeS < sport.minDurationS) {
      throw invalid("movingTimeS", `The activity must last at least ${sport.minDurationS} s in motion`);
    }
    if (sport.tracksDistance && request.distanceM !== undefined && request.distanceM < sport.minDistanceM) {
      throw invalid("distanceM", `The activity must cover at least ${sport.minDistanceM} m`);
    }
  }

  /** Existing id (ADR-019 §1): a new upload URL only while the trace is still awaited. */
  private async replay(userId: string, row: ActivityRecord): Promise<CreateActivityResult> {
    if (row.userId !== userId) {
      throw new ConflictException({ code: "id_conflict", message: "This id is already used" });
    }
    const uploadUrl =
      row.processingStatus === "pending" ? await presignTraceUpload(this.storage, row) : undefined;
    return { activity: toActivityRecord(row), uploadUrl, created: false };
  }
}

function invalid(field: string, message: string): UnprocessableEntityException {
  return new UnprocessableEntityException({
    code: "validation_error",
    message,
    details: [{ field, message }],
  });
}

/** Pre-signed `PUT` of the trace (ADR-019 §1-2): 15 minutes, enforced content type. */
export async function presignTraceUpload(
  storage: StorageService,
  activity: { id: string; userId: string },
): Promise<UploadUrlResponse> {
  const presigned = await storage.presignPut(
    activityTraceKey(activity.userId, activity.id),
    ACTIVITY_TRACE_CONTENT_TYPE,
  );
  return { uploadUrl: presigned.url, expiresAt: presigned.expiresAt.toISOString() };
}
