import {
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import {
  activityImportSourceKey,
  type ActivityImport,
  type CreateActivityImportRequest,
  type UploadUrlResponse,
} from "@repo/contracts";
import { SportsService } from "../../sports/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { toActivityImport } from "../domain/activity-import-record.js";
import { ImportRateLimiter } from "../services/import-rate-limiter.js";

/** The three formats have no reliable MIME type on iOS (ADR-028 §3). */
export const IMPORT_UPLOAD_CONTENT_TYPE = "application/octet-stream";

export interface CreateActivityImportResult {
  import: ActivityImport;
  upload?: UploadUrlResponse;
  /** `true` -> `201`, `false` -> `200` (replayed call). */
  created: boolean;
}

/**
 * `POST /v1/activity-imports` (ADR-028 §3): idempotent on the
 * app-generated id. Only new imports count toward the rate limit.
 */
@Injectable()
export class CreateActivityImportUseCase {
  constructor(
    private readonly imports: ActivityImportRepository,
    private readonly sports: SportsService,
    private readonly storage: StorageService,
    private readonly rateLimiter: ImportRateLimiter,
  ) {}

  async execute(userId: string, request: CreateActivityImportRequest): Promise<CreateActivityImportResult> {
    const existing = await this.imports.findById(request.id);
    if (existing) {
      return this.replay(userId, existing);
    }

    if (request.sportTypeCode) {
      const sport = await this.sports.findByCode(request.sportTypeCode);
      if (!sport || !sport.isActive) {
        throw new UnprocessableEntityException({
          code: "validation_error",
          message: "Unknown or inactive sport type",
          details: [{ field: "sportTypeCode", message: "Unknown or inactive sport type" }],
        });
      }
    }

    const limit = await this.rateLimiter.hit(userId);
    if (!limit.allowed) {
      throw new HttpException(
        {
          code: "rate_limited",
          message: "Too many imports, try again later",
          retryAfterS: limit.retryAfterS,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const inserted = await this.imports.insertIfAbsent({
      id: request.id,
      userId,
      format: request.format,
      originalFileName: request.fileName,
      sizeBytes: request.sizeBytes,
      requestedSportTypeCode: request.sportTypeCode,
      requestedTitle: request.title,
      requestedVisibility: request.visibility,
    });
    const row = await this.imports.findById(request.id);
    if (!row) {
      throw new Error(`Import ${request.id} vanished right after insert`);
    }
    if (!inserted) {
      // Lost a race with a concurrent replay of the same `POST`.
      return this.replay(userId, row);
    }
    return { import: toActivityImport(row), upload: await this.presign(row), created: true };
  }

  private async replay(
    userId: string,
    row: NonNullable<Awaited<ReturnType<ActivityImportRepository["findById"]>>>,
  ): Promise<CreateActivityImportResult> {
    if (row.userId !== userId) {
      throw new ConflictException({ code: "id_conflict", message: "This id is already used" });
    }
    const upload = row.status === "pending" ? await this.presign(row) : undefined;
    return { import: toActivityImport(row), upload, created: false };
  }

  private async presign(row: { id: string; userId: string; format: "gpx" | "tcx" | "fit" }) {
    const presigned = await this.storage.presignPut(
      activityImportSourceKey(row.userId, row.id, row.format),
      IMPORT_UPLOAD_CONTENT_TYPE,
    );
    return { uploadUrl: presigned.url, expiresAt: presigned.expiresAt.toISOString() };
  }
}
