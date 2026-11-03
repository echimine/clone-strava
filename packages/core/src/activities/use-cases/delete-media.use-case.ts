import { Inject, Injectable, Logger } from "@nestjs/common";
import { activityMediaPrefix } from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AuthorActivityResolver } from "../services/author-activity-resolver.js";

/**
 * `DELETE /v1/activities/:id/media/:mediaId` (ADR-037 §4): deletes the row, then the Media's
 * folder, also when the row is already gone (files of a Media never confirmed). If that Media was
 * first, the map comes first again (`media_first = false`).
 */
@Injectable()
export class DeleteMediaUseCase {
  private readonly logger = new Logger(DeleteMediaUseCase.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly authorActivity: AuthorActivityResolver,
    private readonly activities: ActivityRepository,
    private readonly media: ActivityMediaRepository,
    private readonly storage: StorageService,
  ) {}

  async execute(userId: string, activityId: string, mediaId: string): Promise<void> {
    const activity = await this.authorActivity.resolve(userId, activityId);
    await this.db.transaction(async (tx) => {
      // Locked so a concurrent reorder or confirmation cannot change which Media is first.
      const locked = await this.activities.findForUpdate(activity.id, tx);
      if (!locked) {
        return;
      }
      const wasFirst = (await this.media.findFirstId(activity.id, tx)) === mediaId;
      if ((await this.media.delete(activity.id, mediaId, tx)) && wasFirst && locked.mediaFirst) {
        await this.activities.clearMediaFirst(activity.id, tx);
      }
    });

    // After the commit (ADR-021 §3). The row is gone: files left behind are unreachable, so a
    // failure is only logged and the daily `bucket-sweep` catches them (ADR-037 §11).
    try {
      await this.storage.deleteFolder(activityMediaPrefix(activity.userId, activity.id, mediaId));
    } catch (error: unknown) {
      this.logger.warn(`Files of deleted Media ${mediaId} not removed: ${String(error)}`);
    }
  }
}
