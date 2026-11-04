import { Injectable } from "@nestjs/common";
import { AVATARS_BUCKET_PREFIX, parseAvatarKey } from "@repo/contracts";
import { StorageService, staleFolderKeys } from "../../storage/index.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";

/**
 * The `users` part of the daily `bucket-sweep` (ADR-037 §11): deletes every
 * `avatars/{userId}/{avatarId}.jpg` that is not the athlete's current `avatar_key`, once 7 days
 * old (a replaced or removed Avatar whose delete failed, an upload never stored). Keys outside
 * this layout are left alone. Returns the number of objects deleted.
 */
@Injectable()
export class SweepAvatarsUseCase {
  constructor(
    private readonly userProfiles: UserProfileRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(now = new Date()): Promise<number> {
    const objects = (await this.storage.listKeys(AVATARS_BUCKET_PREFIX)).flatMap((object) => {
      const parts = parseAvatarKey(object.key);
      return parts ? [{ ...object, userId: parts.userId }] : [];
    });
    const userIds = [...new Set(objects.map((object) => object.userId))];
    const current = new Set((await this.userProfiles.findByIds(userIds)).map((profile) => profile.avatarKey));
    // One Avatar per folder: each key is judged on its own.
    const keys = staleFolderKeys(
      objects.filter((object) => !current.has(object.key)),
      (object) => object.key,
      now,
    );
    await this.storage.deleteObjects(keys);
    return keys.length;
  }
}
