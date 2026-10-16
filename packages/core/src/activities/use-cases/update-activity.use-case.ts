import {
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  UnprocessableEntityException,
} from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_UPDATED_EVENT,
  type ActivityChangedField,
  type ActivityUpdatedEvent,
  type UpdateActivityRequest,
} from "@repo/contracts";
import { SportsService } from "../../sports/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { ReprocessJobEnqueuer } from "../services/reprocess-job-enqueuer.js";
import { GetVisibleActivityUseCase } from "./get-visible-activity.use-case.js";

type ActivityRow = NonNullable<Awaited<ReturnType<GetVisibleActivityUseCase["findRow"]>>>;

/**
 * `PATCH /v1/activities/:id` (ADR-033 §4): the author edits the title, description, sport or
 * visibility of their processed activity. Not visible: `404`; visible but someone else's:
 * `403`; not `processed`: `409`. A new sport must accept the official values (its minimums),
 * otherwise `422`. One `UPDATE`, last write wins, then `activities.activity.updated` and, when
 * the sport changed, `reprocess-activity` (ADR-033 §5).
 */
@Injectable()
export class UpdateActivityUseCase {
  private readonly logger = new Logger(UpdateActivityUseCase.name);

  constructor(
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly getVisibleActivity: GetVisibleActivityUseCase,
    private readonly sports: SportsService,
    private readonly events: EventEmitter2,
    private readonly reprocessEnqueuer: ReprocessJobEnqueuer,
  ) {}

  async execute(userId: string, activityId: string, request: UpdateActivityRequest): Promise<void> {
    const row = await this.getVisibleActivity.findRow(userId, activityId);
    if (!row) {
      throw activityNotFound();
    }
    if (row.userId !== userId) {
      throw new ForbiddenException({
        code: "not_activity_author",
        message: "Only the author can edit this activity",
      });
    }
    if (row.processingStatus !== "processed") {
      throw notEditable();
    }
    const values = {
      title: request.title,
      description: toStoredDescription(request.description),
      sportTypeCode: request.sportTypeCode,
      visibility: request.visibility,
    };
    if (values.sportTypeCode !== undefined && values.sportTypeCode !== row.sportTypeCode) {
      await this.validateSportChange(row.id, values.sportTypeCode);
    }

    const updated = await this.activities.updateIfProcessed(row.id, values);
    if (!updated) {
      // Deleted (or no longer processed) by a concurrent request in between.
      if (await this.activities.findById(row.id)) {
        throw notEditable();
      }
      throw activityNotFound();
    }

    // After the commit (ADR-021 §3). An edit that changes nothing has nothing to tell.
    const changedFields = changedFieldsBetween(row, updated);
    if (changedFields.length > 0) {
      const event: ActivityUpdatedEvent = { activityId: row.id, userId, changedFields };
      this.events.emit(ACTIVITY_UPDATED_EVENT, event);
    }
    if (changedFields.includes("sportTypeCode")) {
      await this.enqueueReprocessing(row.id, userId, updated.updatedAt);
    }
  }

  /**
   * Must-happen reaction (ADR-033 §5, ADR-021 §3): the official values follow the sport. The
   * edit is committed, so a failed enqueue does not fail it: the reconciliation sweep
   * (ADR-019 §7) enqueues the job later.
   */
  private async enqueueReprocessing(activityId: string, userId: string, updatedAt: Date): Promise<void> {
    try {
      await this.reprocessEnqueuer.enqueue({ activityId, userId }, updatedAt);
    } catch (error) {
      this.logger.error(
        `Could not enqueue reprocess-activity for ${activityId}, left to reconciliation: ${String(error)}`,
      );
    }
  }

  /**
   * ADR-033 §4: an active sport whose minimums the official values meet (moving time, and
   * distance for GPS sports, as on import, ADR-031 §11). A value the worker did not compute is
   * not held against the athlete.
   */
  private async validateSportChange(activityId: string, sportTypeCode: string): Promise<void> {
    const sport = await this.sports.findByCode(sportTypeCode);
    if (!sport || !sport.isActive) {
      throw new UnprocessableEntityException({
        code: "validation_error",
        message: "Unknown or inactive sport type",
        details: [{ field: "sportTypeCode", message: "Unknown or inactive sport type" }],
      });
    }
    const [stats] = await this.activityStats.findByActivityIds([activityId]);
    const tooShort = stats?.movingTimeS != null && stats.movingTimeS < sport.minDurationS;
    const tooNear = sport.usesGps && stats?.distanceM != null && stats.distanceM < sport.minDistanceM;
    if (tooShort || tooNear) {
      throw new UnprocessableEntityException({
        code: "activity_too_short_for_sport",
        message: tooShort
          ? `The activity must last at least ${sport.minDurationS} s in motion for this sport`
          : `The activity must cover at least ${sport.minDistanceM} m for this sport`,
      });
    }
  }
}

const EDITABLE_FIELDS = ["title", "description", "sportTypeCode", "visibility"] as const satisfies ActivityChangedField[];

/** `undefined` leaves it as is; `null`, empty or blank clears it. */
function toStoredDescription(description: string | null | undefined): string | null | undefined {
  if (description === undefined) {
    return undefined;
  }
  return description?.trim() ? description : null;
}

function changedFieldsBetween(before: ActivityRow, after: ActivityRow): ActivityChangedField[] {
  return EDITABLE_FIELDS.filter((field) => before[field] !== after[field]);
}

function notEditable(): ConflictException {
  return new ConflictException({
    code: "activity_not_editable",
    message: "Only a processed activity can be edited",
  });
}
