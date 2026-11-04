import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job } from "bullmq";
import { AVATARS_QUEUE_NAME, COPY_GOOGLE_AVATAR_JOB_NAME, copyGoogleAvatarJobSchema } from "@repo/contracts";
import { PhotoUnusableError, UsersService } from "@repo/core/users";

/**
 * The `copy-google-avatar` job (ADR-037 §2): parses it and hands it to
 * `UsersService.copyGoogleAvatar`. A photo that will never copy fails the job for good; any other
 * error is retried, then given up: the athlete keeps their initials.
 */
@Processor(AVATARS_QUEUE_NAME, { concurrency: 4 })
export class CopyGoogleAvatarProcessor extends WorkerHost {
  private readonly logger = new Logger(CopyGoogleAvatarProcessor.name);

  constructor(private readonly users: UsersService) {
    super();
  }

  async process(job: Job): Promise<void> {
    if (job.name !== COPY_GOOGLE_AVATAR_JOB_NAME) {
      this.logger.warn(`Unknown job name on queue "${AVATARS_QUEUE_NAME}": ${job.name}`);
      return;
    }
    const parsed = copyGoogleAvatarJobSchema.safeParse(job.data);
    if (!parsed.success) {
      throw new UnrecoverableError(`Invalid ${COPY_GOOGLE_AVATAR_JOB_NAME} payload`);
    }
    const { userId, imageUrl } = parsed.data;
    try {
      const outcome = await this.users.copyGoogleAvatar(userId, imageUrl);
      this.logger.log({ userId, outcome }, "Google photo copy done");
    } catch (error) {
      if (error instanceof PhotoUnusableError) {
        throw new UnrecoverableError(error.message);
      }
      throw error;
    }
  }
}
