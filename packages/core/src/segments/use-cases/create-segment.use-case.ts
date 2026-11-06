import { ConflictException, HttpException, HttpStatus, Inject, Injectable, UnprocessableEntityException } from "@nestjs/common";
import {
  ANALYTICS_EVENTS,
  type CreatedSegment,
  type CreateSegmentRequest,
  type PreviewSegmentRequest,
  type SegmentPreview,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { AnalyticsService } from "../../analytics/index.js";
import { DATABASE } from "../../infrastructure/index.js";
import { SEGMENT_CREATIONS_PER_DAY } from "../domain/segment-geometry.js";
import { SegmentCreationRepository, type StoredSegment } from "../repositories/segment-creation.repository.js";
import { SegmentDuplicates } from "../services/segment-duplicates.js";
import { SegmentHistoryJobs } from "../services/segment-history-jobs.js";
import { SegmentMeasurementService, type SegmentMeasurement } from "../services/segment-measurement.js";

const QUOTA_WINDOW_HOURS = 24;

/**
 * `POST /v1/segments/preview` and `POST /v1/segments` (ADR-039 §5, §7, §12): the app checks the
 * rules, the server checks them again and computes everything from the drawn path. A creation
 * stars the Segment for its creator, then enqueues its retro-matching and `segment_created`.
 */
@Injectable()
export class CreateSegmentUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly segments: SegmentCreationRepository,
    private readonly measurement: SegmentMeasurementService,
    private readonly duplicates: SegmentDuplicates,
    private readonly historyJobs: SegmentHistoryJobs,
    private readonly analytics: AnalyticsService,
  ) {}

  /** Figures, profile, broken rules, duplicate and quota left; nothing written. */
  async preview(userId: string, request: PreviewSegmentRequest): Promise<SegmentPreview> {
    const measured = await this.measurement.measure(request.sport, request.points);
    const [duplicate, recent] = await Promise.all([
      this.duplicates.find(request.sport, measured.track),
      this.segments.countRecent(userId, QUOTA_WINDOW_HOURS),
    ]);
    return {
      ...measured.figures,
      track: measured.trackView,
      violations: measured.violations,
      duplicate,
      quotaLeft: Math.max(0, SEGMENT_CREATIONS_PER_DAY - recent.total),
    };
  }

  /** `422` broken rule (its code), `409 duplicate` (with `existing`), `429 quota` (with `Retry-After`). */
  async create(userId: string, request: CreateSegmentRequest): Promise<CreatedSegment> {
    const measured = await this.measurement.measure(request.sport, request.points);
    if (measured.violations.length > 0) {
      throw new UnprocessableEntityException({
        code: measured.violations[0],
        message: "The drawn path breaks a Segment rule",
        details: measured.violations.map((violation) => ({ field: "points", message: violation })),
      });
    }

    const outcome = await this.db.transaction(async (tx) => {
      await this.segments.lockCreator(userId, tx);
      const recent = await this.segments.countRecent(userId, QUOTA_WINDOW_HOURS, tx);
      if (recent.total >= SEGMENT_CREATIONS_PER_DAY) {
        return { kind: "limited", retryAfterS: Math.max(1, recent.secondsUntilOldestExpires ?? 1) } as const;
      }
      const duplicate = await this.duplicates.find(request.sport, measured.track, tx);
      if (duplicate) {
        return { kind: "duplicate", existing: duplicate } as const;
      }
      const segment = await this.segments.insert(
        {
          name: request.name,
          sportTypeCode: request.sport,
          createdBy: userId,
          figures: measured.figures,
          track: measured.track,
          mapPolyline: measured.mapPolyline,
        },
        tx,
      );
      return { kind: "created", segment } as const;
    });

    if (outcome.kind === "limited") {
      throw new HttpException(
        {
          code: "quota",
          message: `At most ${SEGMENT_CREATIONS_PER_DAY} Segments per 24 hours`,
          retryAfterS: outcome.retryAfterS,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (outcome.kind === "duplicate") {
      throw new ConflictException({ code: "duplicate", message: "This Segment already exists", existing: outcome.existing });
    }

    // After the commit: the retro-matching reads the stored Segment (ADR-039 §7).
    await this.historyJobs.enqueueFirstPage(outcome.segment.id);
    this.analytics.capture(ANALYTICS_EVENTS.SEGMENT_CREATED, userId, { sport: request.sport });
    return toCreatedSegment(outcome.segment, measured);
  }
}

function toCreatedSegment(segment: StoredSegment, measured: SegmentMeasurement): CreatedSegment {
  return {
    id: segment.id,
    name: segment.name,
    sport: segment.sportTypeCode as CreatedSegment["sport"],
    verified: segment.verifiedAt !== null,
    distanceM: segment.distanceM,
    elevationGainM: segment.elevationGainM,
    avgGradePct: segment.avgGrade,
    maxGradePct: segment.maxGrade,
    minAltitudeM: segment.minAltitudeM,
    maxAltitudeM: segment.maxAltitudeM,
    climbCategory: segment.climbCategory,
    track: measured.trackView,
    createdAt: segment.createdAt.toISOString(),
  };
}
