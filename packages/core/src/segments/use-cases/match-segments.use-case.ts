import { Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  SEGMENTS_EFFORTS_MATCHED_EVENT,
  type MatchSegmentsJob,
  type SegmentsEffortsMatchedEvent,
} from "@repo/contracts";
import { simplifyTrack, trackDistanceM } from "@repo/geo";
import { ActivitiesService } from "../../activities/index.js";
import type { FoundEffort } from "../domain/effort-sync.js";
import { matchSegment, SEGMENT_MATCHING_VERSION } from "../domain/match-segment.js";
import { marginInDegrees, SEGMENT_SPORTS } from "../domain/segment-sports.js";
import { ActivityMatchingRepository } from "../repositories/activity-matching.repository.js";
import { SegmentRepository } from "../repositories/segment.repository.js";
import { EffortRecorder } from "../services/effort-recorder.js";

/** Tolerance of the trace passed to the prefilter: it only needs to stay near the real one. */
const PREFILTER_TRACE_TOLERANCE_M = 10;
/** Prefilter margin around the trace: the line half-width plus the simplification, overestimated. */
const PREFILTER_MARGIN_M = 100;

/**
 * `match-segments {activityId}` (ADR-019 §8, ADR-039 §6): idempotent and complete. Recomputes
 * every Effort of the Activity on its stored cleaned trace, keeps those that still exist, inserts
 * the new ones, deletes those that disappeared, writes the matching version, replays the Medals
 * of every (athlete, Segment) touched, and after the commit emits `segments.efforts.matched`.
 * A sport without a map gets no Effort but still its version, so the sweep skips it. A failure
 * never changes the Activity's own status: the job has its own retries.
 */
@Injectable()
export class MatchSegmentsUseCase {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly segments: SegmentRepository,
    private readonly matchings: ActivityMatchingRepository,
    private readonly recorder: EffortRecorder,
    private readonly events: EventEmitter2,
  ) {}

  async execute(job: MatchSegmentsJob): Promise<void> {
    const trace = await this.activities.getMatchingTrace(job.activityId);
    if (!trace) {
      // Deleted, or not processed: its own processing enqueues the matching again.
      return;
    }

    const found: FoundEffort[] = [];
    if (SEGMENT_SPORTS.includes(trace.sportTypeCode) && trace.points.length >= 2) {
      const simplified = simplifyTrack(trace.points, PREFILTER_TRACE_TOLERANCE_M);
      const candidates = await this.segments.findNearTrace(
        trace.sportTypeCode,
        `SRID=4326;LINESTRING(${simplified.map((point) => `${point.lon} ${point.lat}`).join(",")})`,
        marginInDegrees(PREFILTER_MARGIN_M, simplified.map((point) => point.lat)),
      );
      for (const segment of candidates) {
        const segmentDistanceM = segment.distanceM ?? trackDistanceM(segment.path);
        for (const effort of matchSegment(trace, segment.path)) {
          found.push({ ...effort, segmentId: segment.id, segmentDistanceM });
        }
      }
    }

    await this.recorder.record(trace, found, {
      alsoInTransaction: (tx) => this.matchings.upsert(trace.activityId, SEGMENT_MATCHING_VERSION, tx),
    });

    const event: SegmentsEffortsMatchedEvent = {
      activityId: trace.activityId,
      userId: trace.userId,
      requestId: job.requestId,
    };
    this.events.emit(SEGMENTS_EFFORTS_MATCHED_EVENT, event);
  }
}
