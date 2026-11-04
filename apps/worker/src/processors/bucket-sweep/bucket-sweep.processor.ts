import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import type { Job } from "bullmq";
import { BUCKET_SWEEP_JOB_NAME, BUCKET_SWEEP_QUEUE_NAME } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { UsersService } from "@repo/core/users";

/**
 * The safety net of the whole bucket (ADR-037 §11): each module deletes the orphans of its own
 * prefixes, `activities` for `activities/` and `imports/`, `users` for `avatars/`. Both run even
 * if the other fails; the job fails if either did, and the next day's run tries again.
 */
@Processor(BUCKET_SWEEP_QUEUE_NAME)
export class BucketSweepProcessor extends WorkerHost {
  private readonly logger = new Logger(BucketSweepProcessor.name);

  constructor(
    private readonly activities: ActivitiesService,
    private readonly users: UsersService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== BUCKET_SWEEP_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${BUCKET_SWEEP_QUEUE_NAME}": ${job.name}`);
      return;
    }
    const [activities, avatars] = await Promise.allSettled([
      this.activities.sweepBucket(),
      this.users.sweepAvatars(),
    ]);
    this.logger.log(
      { activityObjects: settledCount(activities), avatarObjects: settledCount(avatars) },
      "Bucket swept",
    );
    for (const result of [activities, avatars]) {
      if (result.status === "rejected") {
        throw result.reason;
      }
    }
  }
}

function settledCount(result: PromiseSettledResult<number>): number | string {
  return result.status === "fulfilled" ? result.value : `failed: ${String(result.reason)}`;
}
