import { randomUUID } from "node:crypto";
import { Injectable, Logger } from "@nestjs/common";
import { AVATAR_CONTENT_TYPE, avatarKey } from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { downloadPhoto, encodeAvatarJpeg, googlePhotoUrlAtAvatarSize } from "../services/google-photo.js";
import { SetAvatarUseCase } from "./set-avatar.use-case.js";

/** What the copy of the Google photo did. */
export type GoogleAvatarCopy = "copied" | "already_set" | "set_meanwhile";

/**
 * Copies the Google photo of a new account as its Avatar (ADR-037 §2), only if the athlete has
 * none. Downloads `imageUrl` (`user.image`, read by `auth`), re-encodes it as a 512×512 JPEG, puts
 * it under `avatars/{userId}/{avatarId}.jpg` and stores it with `onlyIfAbsent`. When the Avatar
 * was set meanwhile, or the database failed, the copy is deleted (a failure is only logged: the
 * `bucket-sweep` catches it).
 *
 * A photo that will never copy (`4xx`, over 10 MB, not an image) throws `PhotoUnusableError`; a
 * network error or a `5xx` throws a plain error, for the caller to retry.
 */
@Injectable()
export class CopyGoogleAvatarUseCase {
  private readonly logger = new Logger(CopyGoogleAvatarUseCase.name);

  constructor(
    private readonly profiles: UserProfileRepository,
    private readonly setAvatar: SetAvatarUseCase,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, imageUrl: string): Promise<GoogleAvatarCopy> {
    // Nothing is downloaded for an athlete who already has an Avatar (replay, backfill).
    if ((await this.profiles.findById(userId))?.avatarKey) {
      return "already_set";
    }
    const jpeg = await encodeAvatarJpeg(await downloadPhoto(googlePhotoUrlAtAvatarSize(imageUrl)));
    const avatarId = randomUUID();
    const key = avatarKey(userId, avatarId);
    await this.storage.putObject(key, jpeg, { contentType: AVATAR_CONTENT_TYPE });
    let stored = false;
    try {
      stored = await this.setAvatar.execute(userId, avatarId, { onlyIfAbsent: true });
    } finally {
      if (!stored) {
        // Set meanwhile by the athlete, or the database failed: the copy is nobody's Avatar.
        await this.deleteQuietly(key);
      }
    }
    return stored ? "copied" : "set_meanwhile";
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
