import { ConflictException, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_DELETED_EVENT,
  activityImportSourceKey,
  activityPrefix,
  type ActivityDeletedEvent,
} from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";

/**
 * The one way an Activity is deleted (ADR-033 §6), by its author or as a Sanction (ADR-038 §11):
 * hard delete unless the worker is processing it (`409 not_deletable`), then
 * `activities.activity.deleted`, then its stored files: everything under its folder (trace,
 * Media, Media still being sent) and the import's original file (ADR-037 §11). The caller has
 * checked who may delete it.
 */
@Injectable()
export class ActivityRemover {
  private readonly logger = new Logger(ActivityRemover.name);

  constructor(
    private readonly activities: ActivityRepository,
    private readonly imports: ActivityImportRepository,
    private readonly storage: StorageService,
    private readonly events: EventEmitter2,
  ) {}

  async remove(activity: { id: string; userId: string }, options: { bySanction: boolean }): Promise<void> {
    // Read before the delete, so nothing after the commit can fail the request.
    const importKey = await this.importKey(activity.userId, activity.id);
    if (!(await this.activities.deleteUnlessProcessing(activity.id))) {
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

  /** The original file of an imported activity (the import id is the activity id, ADR-028 §1). */
  private async importKey(userId: string, activityId: string): Promise<string | undefined> {
    const activityImport = await this.imports.findById(activityId);
    return activityImport?.userId === userId
      ? activityImportSourceKey(userId, activityId, activityImport.format)
      : undefined;
  }
}
