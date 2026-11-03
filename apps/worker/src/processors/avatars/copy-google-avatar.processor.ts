import { randomUUID } from "node:crypto";
import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { UnrecoverableError, type Job } from "bullmq";
import {
  AVATAR_CONTENT_TYPE,
  AVATARS_QUEUE_NAME,
  COPY_GOOGLE_AVATAR_JOB_NAME,
  avatarKey,
  copyGoogleAvatarJobSchema,
} from "@repo/contracts";
import { StorageService } from "@repo/core/storage";
import { UsersService } from "@repo/core/users";
import {
  PhotoUnusableError,
  downloadPhoto,
  encodeAvatarJpeg,
  googlePhotoUrlAtAvatarSize,
} from "./google-photo.js";

/**
 * Copies the Google photo of a new account as its Avatar (ADR-037 §2), only if the athlete has
 * none. Downloads `user.image`, re-encodes it as a 512×512 JPEG, puts it under
 * `avatars/{userId}/{avatarId}.jpg` and stores it with `UsersService.setAvatar(…, { onlyIfAbsent })`.
 * Retried on technical errors, then given up: the athlete keeps their initials.
 */
@Processor(AVATARS_QUEUE_NAME, { concurrency: 4 })
export class CopyGoogleAvatarProcessor extends WorkerHost {
  private readonly logger = new Logger(CopyGoogleAvatarProcessor.name);

  constructor(
    private readonly users: UsersService,
    private readonly storage: StorageService,
  ) {
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
    // Nothing is downloaded for an athlete who already has an Avatar (replay, backfill).
    if ((await this.users.getSummary(userId))?.avatarKey) {
      this.logger.log({ userId }, "Avatar already set, Google photo not copied");
      return;
    }
    const jpeg = await this.encode(imageUrl);
    const avatarId = randomUUID();
    const key = avatarKey(userId, avatarId);
    await this.storage.putObject(key, jpeg, { contentType: AVATAR_CONTENT_TYPE });
    let stored = false;
    try {
      stored = await this.users.setAvatar(userId, avatarId, { onlyIfAbsent: true });
    } finally {
      if (!stored) {
        // Set meanwhile by the athlete, or the database failed: the copy is nobody's Avatar.
        await this.deleteQuietly(key);
      }
    }
    this.logger.log({ userId, stored }, stored ? "Google photo copied as the Avatar" : "Avatar set meanwhile");
  }

  private async encode(imageUrl: string): Promise<Uint8Array> {
    try {
      return await encodeAvatarJpeg(await downloadPhoto(googlePhotoUrlAtAvatarSize(imageUrl)));
    } catch (error) {
      if (error instanceof PhotoUnusableError) {
        throw new UnrecoverableError(error.message);
      }
      throw error;
    }
  }

  private async deleteQuietly(key: string): Promise<void> {
    try {
      await this.storage.deleteObject(key);
    } catch (error) {
      // The daily bucket-sweep deletes it after 7 days (ADR-037 §11).
      this.logger.warn({ key, error: String(error) }, "Unused Google photo copy left in the bucket");
    }
  }
}
