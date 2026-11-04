import { Inject, Injectable, Logger } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { MEDIA_DELETED_EVENT, activityMediaPrefix, type MediaDeletedEvent } from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";

/**
 * The one way a Media is deleted (ADR-037 §4), by the Activity's author or as a Sanction
 * (ADR-038 §11): deletes the row, then the Media's folder, also when the row is already gone
 * (files of a Media never confirmed). If that Media was first, the map comes first again
 * (`media_first = false`). `activities.media.deleted` follows a deleted row. The caller has
 * checked who may delete it.
 */
@Injectable()
export class MediaRemover {
  private readonly logger = new Logger(MediaRemover.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly activities: ActivityRepository,
    private readonly media: ActivityMediaRepository,
    private readonly storage: StorageService,
    private readonly events: EventEmitter2,
  ) {}

  /** Whether a row was deleted. */
  async remove(
    activity: { id: string; userId: string },
    mediaId: string,
    options: { bySanction: boolean },
  ): Promise<boolean> {
    const deleted = await this.db.transaction(async (tx) => {
      // Locked so a concurrent reorder or confirmation cannot change which Media is first.
      const locked = await this.activities.findForUpdate(activity.id, tx);
      if (!locked) {
        return false;
      }
      const wasFirst = (await this.media.findFirstId(activity.id, tx)) === mediaId;
      const removed = await this.media.delete(activity.id, mediaId, tx);
      if (removed && wasFirst && locked.mediaFirst) {
        await this.activities.clearMediaFirst(activity.id, tx);
      }
      return removed;
    });

    // After the commit (ADR-021 §3).
    if (deleted) {
      const event: MediaDeletedEvent = {
        mediaId,
        activityId: activity.id,
        userId: activity.userId,
        bySanction: options.bySanction,
      };
      this.events.emit(MEDIA_DELETED_EVENT, event);
    }
    // The row is gone: files left behind are unreachable, so a failure is only logged and the
    // daily `bucket-sweep` catches them (ADR-037 §11).
    try {
      await this.storage.deleteFolder(activityMediaPrefix(activity.userId, activity.id, mediaId));
    } catch (error: unknown) {
      this.logger.warn(`Files of deleted Media ${mediaId} not removed: ${String(error)}`);
    }
    return deleted;
  }
}
