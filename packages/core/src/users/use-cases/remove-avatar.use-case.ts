import { Inject, Injectable, Logger } from "@nestjs/common";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { deleteOldAvatar } from "../services/delete-old-avatar.js";

/**
 * `DELETE /v1/me/avatar` (ADR-037 §2): the athlete is shown with their initials again. Without an
 * Avatar, nothing happens. The object is deleted right after the commit.
 */
@Injectable()
export class RemoveAvatarUseCase {
  private readonly logger = new Logger(RemoveAvatarUseCase.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly profiles: UserProfileRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string): Promise<void> {
    const oldKey = await this.db.transaction(async (tx) => {
      await this.profiles.insertIfAbsent(userId, tx);
      const key = await this.profiles.lockAvatarKey(userId, tx);
      if (key !== null) {
        await this.profiles.setAvatarKey(userId, null, tx);
      }
      return key;
    });
    await deleteOldAvatar(this.storage, this.logger, oldKey);
  }
}
