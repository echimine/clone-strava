import { ConflictException, Inject, Injectable, Logger } from "@nestjs/common";
import { AVATAR_MAX_BYTES, avatarKey } from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { deleteOldAvatar } from "./delete-old-avatar.js";

/**
 * Stores an object already in the bucket as the Avatar (ADR-037 §2): `PUT /v1/me/avatar` after the
 * phone's upload, and the copy of the Google photo. The key is always built from the caller's own
 * id. The previous object is deleted right after the commit.
 */
@Injectable()
export class SetAvatarUseCase {
  private readonly logger = new Logger(SetAvatarUseCase.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly profiles: UserProfileRepository,
    private readonly storage: StorageService,
  ) {}

  /**
   * `409 avatar_missing` when the object is absent (`HEAD`), `409 avatar_too_large` over 1 MB.
   * With `onlyIfAbsent`, an Avatar already set is kept (checked under a row lock). `true` when
   * `avatarId` is now the Avatar.
   */
  async execute(userId: string, avatarId: string, options: { onlyIfAbsent?: boolean } = {}): Promise<boolean> {
    const key = avatarKey(userId, avatarId);
    const object = await this.storage.headObject(key);
    if (!object) {
      throw new ConflictException({ code: "avatar_missing", message: "The Avatar was not uploaded" });
    }
    if (object.sizeBytes > AVATAR_MAX_BYTES) {
      throw new ConflictException({ code: "avatar_too_large", message: "The Avatar is larger than 1 MB" });
    }
    const outcome = await this.db.transaction(async (tx) => {
      await this.profiles.insertIfAbsent(userId, tx);
      const previousKey = await this.profiles.lockAvatarKey(userId, tx);
      if (previousKey !== null && options.onlyIfAbsent) {
        return { stored: false, oldKey: null };
      }
      await this.profiles.setAvatarKey(userId, key, tx);
      // A replay of the same `avatarId` keeps its object.
      return { stored: true, oldKey: previousKey === key ? null : previousKey };
    });
    await deleteOldAvatar(this.storage, this.logger, outcome.oldKey);
    return outcome.stored;
  }
}
