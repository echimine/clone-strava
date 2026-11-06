import { Injectable } from "@nestjs/common";
import type { MatchSegmentHistoryJob } from "@repo/contracts";
import { trackDistanceM } from "@repo/geo";
import { ActivitiesService } from "../../activities/index.js";
import { matchSegment } from "../domain/match-segment.js";
import { DEFAULT_PRIVACY_ZONE_RADIUS_M } from "../domain/segment-sports.js";
import { SegmentRepository, type SegmentToMatch } from "../repositories/segment.repository.js";
import { EffortRecorder } from "../services/effort-recorder.js";

/** ADR-039 §7: candidate Activities per page. */
export const SEGMENT_HISTORY_PAGE_SIZE = 200;

/**
 * One page of `match-segment-history {segmentId, cursor}` (ADR-039 §7): matches the new Segment
 * on every Activity of its sport whose route passes near its start and end, whatever their
 * visibility, the whole history; the first page takes all of the creator's Activities, then
 * everyone else's by pages. Each Activity's Efforts on this Segment are replaced and the
 * athlete's Medals on it replayed. Returns the cursor of the next page, or `null` once the last
 * page has set `history_matched_at`, or when the Segment is gone.
 */
@Injectable()
export class MatchSegmentHistoryUseCase {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly segments: SegmentRepository,
    private readonly recorder: EffortRecorder,
  ) {}

  async execute(job: MatchSegmentHistoryJob): Promise<{ nextCursor: string } | null> {
    const segment = await this.segments.findById(job.segmentId);
    if (!segment) {
      // Deleted: the retro-matching stops (ADR-039 §11).
      return null;
    }
    const near = {
      sportTypeCode: segment.sportTypeCode,
      start: segment.start,
      end: segment.end,
      marginM: 2 * DEFAULT_PRIVACY_ZONE_RADIUS_M,
      limit: SEGMENT_HISTORY_PAGE_SIZE,
    };

    if (job.cursor === null && segment.createdBy) {
      let cursor: string | undefined;
      do {
        const page = await this.activities.findActivitiesNearPath({ ...near, cursor, userId: segment.createdBy });
        await this.matchActivities(segment, page.activities);
        cursor = page.nextCursor ?? undefined;
      } while (cursor);
    }

    const page = await this.activities.findActivitiesNearPath({
      ...near,
      cursor: job.cursor ?? undefined,
      excludeUserId: segment.createdBy ?? undefined,
    });
    await this.matchActivities(segment, page.activities);
    if (page.nextCursor) {
      return { nextCursor: page.nextCursor };
    }
    await this.segments.markHistoryMatched(segment.id);
    return null;
  }

  private async matchActivities(segment: SegmentToMatch, activities: Array<{ id: string }>): Promise<void> {
    const segmentDistanceM = segment.distanceM ?? trackDistanceM(segment.path);
    for (const { id } of activities) {
      const trace = await this.activities.getMatchingTrace(id);
      if (!trace || trace.sportTypeCode !== segment.sportTypeCode) {
        continue;
      }
      const found = matchSegment(trace, segment.path).map((effort) => ({
        ...effort,
        segmentId: segment.id,
        segmentDistanceM,
      }));
      await this.recorder.record(trace, found, { onlySegmentId: segment.id });
    }
  }
}
