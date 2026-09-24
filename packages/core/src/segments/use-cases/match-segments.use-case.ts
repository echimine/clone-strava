import { Injectable, NotImplementedException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { SEGMENTS_EFFORTS_MATCHED_EVENT, type MatchSegmentsJob } from "@repo/contracts";
import { SegmentRepository } from "../repositories/segment.repository.js";
import { SegmentEffortRepository } from "../repositories/segment-effort.repository.js";

/**
 * `match-segments` job logic (ADR-011, ADR-019 §8): enqueued after
 * `process-activity`, does not delay official values. A failure here never
 * changes the activity's own status (ADR-019 §8): it has its own retries.
 * `private` activities are excluded from public leaderboards.
 */
@Injectable()
export class MatchSegmentsUseCase {
  constructor(
    private readonly segments: SegmentRepository,
    private readonly segmentEfforts: SegmentEffortRepository,
    private readonly events: EventEmitter2,
  ) {}

  async execute(_job: MatchSegmentsJob): Promise<void> {
    throw new NotImplementedException();
    // After committing every matched effort:
    // this.events.emit(SEGMENTS_EFFORTS_MATCHED_EVENT, { activityId, userId, requestId })
  }
}
