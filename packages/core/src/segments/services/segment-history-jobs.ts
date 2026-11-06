import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  MATCH_SEGMENT_HISTORY_JOB_NAME,
  SEGMENT_JOB_PRIORITY,
  SEGMENTS_QUEUE_NAME,
  matchSegmentHistoryJobId,
  type MatchSegmentHistoryJob,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY, enqueueUnique } from "../../infrastructure/index.js";

/**
 * Starts a new Segment's retro-matching (ADR-039 §7): the first page of
 * `match-segment-history` (the creator's Activities first), at the history priority, below
 * `match-segments`; `apps/worker` chains the next pages.
 */
@Injectable()
export class SegmentHistoryJobs {
  constructor(@InjectQueue(SEGMENTS_QUEUE_NAME) private readonly queue: Queue<MatchSegmentHistoryJob>) {}

  enqueueFirstPage(segmentId: string): Promise<boolean> {
    return enqueueUnique(
      this.queue,
      MATCH_SEGMENT_HISTORY_JOB_NAME,
      { segmentId, cursor: null },
      matchSegmentHistoryJobId(segmentId, null),
      { ...DEFAULT_JOB_RETRY, priority: SEGMENT_JOB_PRIORITY.history },
    );
  }
}
