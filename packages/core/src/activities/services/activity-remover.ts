import { ConflictException, Inject, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_DELETED_EVENT,
  activityImportSourceKey,
  activityPrefix,
  type ActivityDeletedEvent,
} from "@repo/contracts";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { BestEffortWriter } from "./best-effort-writer.js";

/**
 * The one way an Activity is deleted (ADR-033 §6), by its author or as a Sanction (ADR-038 §11):
 * hard delete unless the worker is processing it (`409 not_deletable`), replaying in the same
 * transaction the athlete's Medals on the distances of its Best efforts (ADR-039 §8), then
 * `activities.activity.deleted`, then its stored files: everything under its folder (trace,
 * Media, Media still being sent) and the import's original file (ADR-037 §11). The caller has
 * checked who may delete it.
 */
@Injectable()
export class ActivityRemover {
  private readonly logger = new Logger(ActivityRemover.name);

  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly activities: ActivityRepository,
    private readonly imports: ActivityImportRepository,
    private readonly storage: StorageService,
    private readonly events: EventEmitter2,
    private readonly bestEfforts: BestEffortWriter,
  ) {}

  async remove(activity: { id: string; userId: string }, options: { bySanction: boolean }): Promise<void> {
    // Read before the delete, so nothing after the commit can fail the request.
    const importKey = await this.importKey(activity.userId, activity.id);
    if (!(await this.deleteAndReplayMedals(activity))) {
      if (await this.activities.findById(activity.id)) {
        throw new ConflictException({
          code: "not_deletable",
          message: "An activity being processed cannot be deleted",
        });
      }
      // Deleted by a concurrent request in between.
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }

    // After the commit (ADR-021 §3).
    const event: ActivityDeletedEvent = {
      activityId: activity.id,
      userId: activity.userId,
      bySanction: options.bySanction,
    };
    this.events.emit(ACTIVITY_DELETED_EVENT, event);
    // The row is gone: files left behind are unreachable, so a failure is only logged and the
    // daily `bucket-sweep` catches them (ADR-037 §11).
    try {
      await this.storage.deleteFolder(activityPrefix(activity.userId, activity.id), importKey ? [importKey] : []);
    } catch (error: unknown) {
      this.logger.warn(`Files of deleted activity ${activity.id} not removed: ${String(error)}`);
    }
  }

  /**
   * Deletes the Activity unless it is `processing`, then replays the Medals of the distances its
   * Best efforts (gone by cascade) held. Locks the `activity` row before the athlete's Best
   * efforts, as processing does; a `processing` row is left before taking the second lock.
   */
  private async deleteAndReplayMedals(activity: { id: string; userId: string }): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const row = await this.activities.findForUpdate(activity.id, tx);
      if (!row || row.processingStatus === "processing") {
        return false;
      }
      const touched = await this.bestEfforts.lockAndReadDistances(activity.userId, activity.id, tx);
      if (!(await this.activities.deleteUnlessProcessing(activity.id, tx))) {
        return false;
      }
      await this.bestEfforts.replay(activity.userId, touched, tx);
      return true;
    });
  }

  /** The original file of an imported activity (the import id is the activity id, ADR-028 §1). */
  private async importKey(userId: string, activityId: string): Promise<string | undefined> {
    const activityImport = await this.imports.findById(activityId);
    return activityImport?.userId === userId
      ? activityImportSourceKey(userId, activityId, activityImport.format)
      : undefined;
  }
}
