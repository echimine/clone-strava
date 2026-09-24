import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import type { Job } from "bullmq";
import { MATCH_SEGMENTS_JOB_NAME, SEGMENTS_QUEUE_NAME, matchSegmentsJobSchema } from "@repo/contracts";
import { SegmentsService } from "@repo/core/segments";

@Processor(SEGMENTS_QUEUE_NAME, { concurrency: 5 })
export class MatchSegmentsProcessor extends WorkerHost {
  private readonly logger = new Logger(MatchSegmentsProcessor.name);

  constructor(private readonly segmentsService: SegmentsService) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== MATCH_SEGMENTS_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${SEGMENTS_QUEUE_NAME}": ${job.name}`);
      return;
    }

    const data = matchSegmentsJobSchema.parse(job.data);
    this.logger.log({ activityId: data.activityId }, "Matching segments");

    // Finds candidate segments near the route (GiST index), verifies the
    // route follows each one end to end, computes the effort time, upserts
    // `segment_effort`, recomputes the segment's leaderboard, then emits
    // `segments.efforts.matched` -- forwarded by the realtime bridge as
    // `activity.segments_matched` (ADR-021 §5) -- all inside
    // `SegmentsService` (ADR-019 §8). A failure here must never change the
    // activity's own `processed` status: this job has its own retries.
    await this.segmentsService.matchSegments(data);
  }
}
