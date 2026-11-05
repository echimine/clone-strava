import { InjectQueue, Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import type { Job, Queue } from "bullmq";
import {
  MATCH_SEGMENT_HISTORY_JOB_NAME,
  MATCH_SEGMENTS_JOB_NAME,
  REPLAY_SEGMENT_MEDALS_JOB_NAME,
  SEGMENT_JOB_PRIORITY,
  SEGMENTS_QUEUE_NAME,
  matchSegmentHistoryJobId,
  matchSegmentHistoryJobSchema,
  matchSegmentsJobSchema,
  matchSegmentsVersionJobId,
  replaySegmentMedalsJobSchema,
} from "@repo/contracts";
import { DEFAULT_JOB_RETRY } from "@repo/core/infrastructure";
import { SEGMENT_MATCHING_VERSION, SegmentsService } from "@repo/core/segments";

/**
 * Job name of the recurring matching sweep (ADR-039 §13). Worker-internal: job chaining and
 * scheduling live in `apps/worker`, never in a `packages/core` module (ADR-021 §2 rule 2).
 */
export const RECONCILE_SEGMENT_MATCHING_JOB_NAME = "reconcile-segment-matching";
/** Every 10 minutes (ADR-039 §13). */
export const RECONCILE_SEGMENT_MATCHING_REPEAT_MS = 10 * 60 * 1000;

/**
 * The `segments` queue (ADR-039 §13). Every job goes through `SegmentsService`; a failure here
 * never changes an Activity's own status: these jobs have their own retries (ADR-019 §8).
 */
@Processor(SEGMENTS_QUEUE_NAME, { concurrency: 5 })
export class SegmentsProcessor extends WorkerHost {
  private readonly logger = new Logger(SegmentsProcessor.name);

  constructor(
    @InjectQueue(SEGMENTS_QUEUE_NAME) private readonly queue: Queue,
    private readonly segmentsService: SegmentsService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    switch (job.name) {
      case MATCH_SEGMENTS_JOB_NAME:
        return this.matchSegments(job);
      case MATCH_SEGMENT_HISTORY_JOB_NAME:
        return this.matchSegmentHistory(job);
      case REPLAY_SEGMENT_MEDALS_JOB_NAME:
        return this.segmentsService.replayMedals(replaySegmentMedalsJobSchema.parse(job.data));
      case RECONCILE_SEGMENT_MATCHING_JOB_NAME:
        return this.reconcile();
      default:
        this.logger.warn(`Unknown job name on queue "${SEGMENTS_QUEUE_NAME}": ${job.name}`);
    }
  }

  /**
   * Recomputes every Effort of the Activity, replays the touched Medals and emits
   * `segments.efforts.matched`, forwarded by the realtime bridge as `activity.segments_matched`
   * (ADR-021 §5, ADR-039 §6).
   */
  private async matchSegments(job: Job): Promise<void> {
    const data = matchSegmentsJobSchema.parse(job.data);
    this.logger.log({ activityId: data.activityId }, "Matching segments");
    await this.segmentsService.matchSegments(data);
  }

  /** One page of a new Segment's retro-matching, then the next page, at a lower priority (§7). */
  private async matchSegmentHistory(job: Job): Promise<void> {
    const data = matchSegmentHistoryJobSchema.parse(job.data);
    this.logger.log({ segmentId: data.segmentId, cursor: data.cursor }, "Matching a segment's history");
    const next = await this.segmentsService.matchSegmentHistory(data);
    if (next) {
      await this.queue.add(
        MATCH_SEGMENT_HISTORY_JOB_NAME,
        { segmentId: data.segmentId, cursor: next.nextCursor },
        {
          ...DEFAULT_JOB_RETRY,
          priority: SEGMENT_JOB_PRIORITY.history,
          jobId: matchSegmentHistoryJobId(data.segmentId, next.nextCursor),
        },
      );
    }
  }

  /**
   * Enqueues `match-segments`, at low priority, for processed Activities never matched or matched
   * with an older version: covers a lost job and a new algorithm version (ADR-039 §13). One job id
   * per version, so a job that failed for good waits for the next version.
   */
  private async reconcile(): Promise<void> {
    const lagging = await this.segmentsService.findActivitiesToMatch();
    await this.queue.addBulk(
      lagging.map(({ activityId, userId }) => ({
        name: MATCH_SEGMENTS_JOB_NAME,
        data: { activityId, userId },
        opts: {
          ...DEFAULT_JOB_RETRY,
          priority: SEGMENT_JOB_PRIORITY.backgroundMatching,
          jobId: matchSegmentsVersionJobId(activityId, SEGMENT_MATCHING_VERSION),
        },
      })),
    );
    this.logger.log(`Segment matching sweep: ${lagging.length} activity(ies) enqueued`);
  }
}
