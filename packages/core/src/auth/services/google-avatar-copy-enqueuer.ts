import { InjectQueue } from "@nestjs/bullmq";
import { Injectable } from "@nestjs/common";
import type { Queue } from "bullmq";
import {
  AVATARS_QUEUE_NAME,
  COPY_GOOGLE_AVATAR_JOB_NAME,
  copyGoogleAvatarJobId,
  copyGoogleAvatarJobSchema,
  type CopyGoogleAvatarJob,
} from "@repo/contracts";
import { enqueueUnique } from "../../infrastructure/index.js";

/**
 * Enqueues `copy-google-avatar` (ADR-037 §2): `auth` owns `user.image` but cannot call `users`
 * (ADR-021 §2), so the worker does the copy. One job id per account, the default retry policy.
 */
@Injectable()
export class GoogleAvatarCopyEnqueuer {
  constructor(@InjectQueue(AVATARS_QUEUE_NAME) private readonly queue: Queue<CopyGoogleAvatarJob>) {}

  /**
   * `false` when nothing was enqueued: a copy of this account is already waiting or running, or
   * `imageUrl` is not an `https` URL the worker would fetch.
   */
  async enqueue(userId: string, imageUrl: string): Promise<boolean> {
    const job = copyGoogleAvatarJobSchema.safeParse({ userId, imageUrl });
    if (!job.success) {
      return false;
    }
    return enqueueUnique(this.queue, COPY_GOOGLE_AVATAR_JOB_NAME, job.data, copyGoogleAvatarJobId(userId));
  }
}
