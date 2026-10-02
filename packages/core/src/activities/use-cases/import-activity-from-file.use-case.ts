import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { Inject, Injectable, Logger } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { parseTrackFile, TrackFileError, type ParsedTrackFile } from "@repo/track-files";
import {
  ACTIVITY_IMPORT_COMPLETED_EVENT,
  ACTIVITY_IMPORT_FAILED_EVENT,
  ACTIVITY_IMPORT_MAX_FILE_BYTES,
  ACTIVITY_IMPORT_MAX_POINTS,
  ANALYTICS_EVENTS,
  activityImportSourceKey,
  activityTraceKey,
  type ActivityImportCompletedEvent,
  type ActivityImportErrorCode,
  type ActivityImportFailedEvent,
  type ImportActivityJob,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { AnalyticsService } from "../../analytics/index.js";
import { DATABASE } from "../../infrastructure/index.js";
import { SportsService } from "../../sports/index.js";
import { ObjectTooLargeError, StorageService } from "../../storage/index.js";
import { UsersService } from "../../users/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import {
  ActivityImportRepository,
  type ActivityImportRow,
} from "../repositories/activity-import.repository.js";
import { PermanentProcessingError } from "../domain/processing-error.js";
import { defaultActivityTitle } from "../domain/import/default-title.js";
import { DUPLICATE_OVERLAP_RATIO, overlapRatio } from "../domain/import/overlap.js";
import { mapFileSportToCode } from "../domain/import/sport-mapping.js";
import { toImportTrace } from "../domain/import/to-import-trace.js";

/** What the `apps/worker` processor needs to chain `process-activity` (ADR-021 §2 rule 2). */
export type ImportActivityResult =
  | { outcome: "imported"; activityId: string }
  | { outcome: "duplicate"; activityId: string }
  | { outcome: "skipped" };

const UNIQUE_VIOLATION = "23505";

/**
 * `import-activity` job logic (ADR-028 §4): download, hash, duplicate
 * check, parse, validate, write the ADR-019 trace, create the activity
 * directly in `processing`. The activity id is the import id (ADR-028
 * §1), which makes the insert idempotent when the job is replayed.
 * Invalid files are recorded as `failed` and rethrown as
 * {@link PermanentProcessingError} (no retry, ADR-028 §7).
 */
@Injectable()
export class ImportActivityFromFileUseCase {
  private readonly logger = new Logger(ImportActivityFromFileUseCase.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly imports: ActivityImportRepository,
    private readonly activities: ActivityRepository,
    private readonly sports: SportsService,
    private readonly users: UsersService,
    private readonly storage: StorageService,
    private readonly analytics: AnalyticsService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: ImportActivityJob): Promise<ImportActivityResult> {
    const row = await this.imports.findById(job.importId);
    if (!row || row.status !== "processing") {
      // Deleted, or already final: a replayed job is a no-op (ADR-028 §4 step 1).
      return { outcome: "skipped" };
    }
    await this.imports.incrementAttempts(row.id);

    const bytes = await this.download(row, job);
    const sha256 = createHash("sha256").update(bytes).digest("hex");

    const sameContent = await this.imports.findImportedBySha256(row.userId, sha256);
    if (sameContent?.activityId) {
      return this.duplicate(row, sameContent.activityId, sha256, job);
    }

    const parsed = await this.parse(row, bytes, sha256, job);
    const traceResult = toImportTrace(parsed);
    if (!traceResult.ok) {
      return this.fail(row, traceResult.code, job, sha256);
    }
    const { trace, startedAt, endedAt } = traceResult;

    const overlapping = await this.activities.findOverlapping(row.userId, startedAt, endedAt);
    const sameWorkout = overlapping.find(
      (activity) =>
        activity.id !== row.id &&
        overlapRatio(
          { startMs: startedAt.getTime(), endMs: endedAt.getTime() },
          { startMs: activity.startedAt.getTime(), endMs: activity.endedAt.getTime() },
        ) > DUPLICATE_OVERLAP_RATIO,
    );
    if (sameWorkout) {
      return this.duplicate(row, sameWorkout.id, sha256, job);
    }

    const sportTypeCode = row.requestedSportTypeCode ?? mapFileSportToCode(parsed.sport);
    const sport = sportTypeCode ? await this.sports.findByCode(sportTypeCode) : undefined;
    if (!sport || !sport.isActive) {
      return this.fail(row, "unknown_sport", job, sha256);
    }
    if ((endedAt.getTime() - startedAt.getTime()) / 1000 < sport.minDurationS) {
      return this.fail(row, "invalid_duration", job, sha256);
    }
    const defaults = await this.users.getActivityDefaults(row.userId);

    // Idempotent PUT: a replay overwrites the trace with identical content (ADR-028 §4 step 9).
    await this.storage.putObject(
      activityTraceKey(row.userId, row.id),
      gzipSync(JSON.stringify(trace)),
      { contentType: "application/json", contentEncoding: "gzip" },
    );

    try {
      await this.db.transaction(async (tx) => {
        await this.activities.insertIfAbsent(
          {
            id: row.id,
            userId: row.userId,
            sportTypeCode: sport.code,
            title:
              row.requestedTitle ??
              (parsed.name?.trim() || defaultActivityTitle(sport.code, startedAt)),
            startedAt,
            endedAt,
            visibility: row.requestedVisibility ?? defaults.defaultVisibility,
            processingStatus: "processing",
            isManual: false,
            source: "imported",
          },
          tx,
        );
        await this.imports.markImported(row.id, { activityId: row.id, sha256 }, tx);
      });
    } catch (error) {
      if (isUniqueViolation(error)) {
        // A concurrent import of the same file won the unique index (ADR-028 §6).
        const winner = await this.imports.findImportedBySha256(row.userId, sha256);
        if (winner?.activityId) {
          return this.duplicate(row, winner.activityId, sha256, job);
        }
      }
      throw error;
    }

    // After the commit (ADR-021 §3): domain event, then analytics.
    this.emitCompleted(row, row.id, "imported", job);
    this.analytics.capture(ANALYTICS_EVENTS.ACTIVITY_IMPORTED, row.userId, {
      format: parsed.format,
      sportTypeCode: sport.code,
    });
    return { outcome: "imported", activityId: row.id };
  }

  /** Technical retries exhausted (ADR-028 §7): called by the worker on the last failed attempt. */
  async markTechnicalFailure(job: ImportActivityJob): Promise<void> {
    const row = await this.imports.findById(job.importId);
    if (row?.status === "processing") {
      await this.recordFailure(row, "processing_error", job);
    }
  }

  private async download(row: ActivityImportRow, job: ImportActivityJob): Promise<Uint8Array> {
    try {
      const bytes = await this.storage.getObject(
        activityImportSourceKey(row.userId, row.id, row.format),
        ACTIVITY_IMPORT_MAX_FILE_BYTES,
      );
      if (bytes === undefined) {
        // `complete` checked it with a `HEAD`: a missing file now is not recoverable.
        return this.fail(row, "invalid_file", job);
      }
      return bytes;
    } catch (error) {
      if (error instanceof ObjectTooLargeError) {
        return this.fail(row, "invalid_file", job);
      }
      throw error;
    }
  }

  private async parse(
    row: ActivityImportRow,
    bytes: Uint8Array,
    sha256: string,
    job: ImportActivityJob,
  ): Promise<ParsedTrackFile> {
    try {
      const parsed = parseTrackFile(bytes, {
        declaredFormat: row.format,
        maxPoints: ACTIVITY_IMPORT_MAX_POINTS,
      });
      if (parsed.format !== row.format) {
        this.logger.warn(
          { importId: row.id, declared: row.format, detected: parsed.format },
          "Declared import format does not match the content; using the content",
        );
      }
      return parsed;
    } catch (error) {
      if (error instanceof TrackFileError) {
        return this.fail(row, error.code, job, sha256);
      }
      throw error;
    }
  }

  private async duplicate(
    row: ActivityImportRow,
    activityId: string,
    sha256: string,
    job: ImportActivityJob,
  ): Promise<ImportActivityResult> {
    await this.imports.markDuplicate(row.id, { activityId, sha256 });
    this.emitCompleted(row, activityId, "duplicate", job);
    return { outcome: "duplicate", activityId };
  }

  private async fail(
    row: ActivityImportRow,
    code: ActivityImportErrorCode,
    job: ImportActivityJob,
    sha256?: string,
  ): Promise<never> {
    await this.recordFailure(row, code, job, sha256);
    throw new PermanentProcessingError(code, `Import ${row.id} failed: ${code}`);
  }

  private async recordFailure(
    row: ActivityImportRow,
    code: ActivityImportErrorCode,
    job: ImportActivityJob,
    sha256?: string,
  ): Promise<void> {
    await this.imports.markFailed(row.id, code, sha256);
    const event: ActivityImportFailedEvent = {
      importId: row.id,
      userId: row.userId,
      code,
      requestId: job.requestId,
    };
    this.events.emit(ACTIVITY_IMPORT_FAILED_EVENT, event);
    this.analytics.capture(ANALYTICS_EVENTS.ACTIVITY_IMPORT_FAILED, row.userId, {
      format: row.format,
      errorCode: code,
    });
  }

  private emitCompleted(
    row: ActivityImportRow,
    activityId: string,
    outcome: ActivityImportCompletedEvent["outcome"],
    job: ImportActivityJob,
  ): void {
    const event: ActivityImportCompletedEvent = {
      importId: row.id,
      activityId,
      userId: row.userId,
      outcome,
      requestId: job.requestId,
    };
    this.events.emit(ACTIVITY_IMPORT_COMPLETED_EVENT, event);
  }
}

function isUniqueViolation(error: unknown): boolean {
  let current: unknown = error;
  // Drizzle wraps the `pg` error in `cause`.
  for (let depth = 0; depth < 3 && current; depth++) {
    if (typeof current === "object" && (current as { code?: unknown }).code === UNIQUE_VIOLATION) {
      return true;
    }
    current = (current as { cause?: unknown }).cause;
  }
  return false;
}
