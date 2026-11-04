import { Injectable } from "@nestjs/common";
import type { MatchSegmentsJob } from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { ActivityEffortRepository } from "./repositories/activity-effort.repository.js";
import type { ActivityEffortRecord } from "./domain/activity-effort.js";

/**
 * Public facade of the `segments` module (ADR-021 §1: layer 3, may depend
 * on `activities`, `sports`).
 */
@Injectable()
export class SegmentsService {
  constructor(
    private readonly matchSegmentsUseCase: MatchSegmentsUseCase,
    private readonly activityEfforts: ActivityEffortRepository,
  ) {}

  /** Called by `apps/worker`'s `match-segments` processor (ADR-011 §1). */
  matchSegments(job: MatchSegmentsJob): Promise<void> {
    return this.matchSegmentsUseCase.execute(job);
  }

  /** An Activity's efforts on Segments, read-only in the backoffice (ADR-038 §11). */
  getActivityEfforts(activityId: string): Promise<ActivityEffortRecord[]> {
    return this.activityEfforts.findByActivityId(activityId);
  }
}
