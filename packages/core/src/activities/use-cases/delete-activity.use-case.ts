import { ConflictException, ForbiddenException, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACTIVITY_DELETED_EVENT,
  activityImportSourceKey,
  activityTraceKey,
  type ActivityDeletedEvent,
} from "@repo/contracts";
import { StorageService } from "../../storage/index.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { GetVisibleActivityUseCase } from "./get-visible-activity.use-case.js";

/**
 * `DELETE /v1/activities/:id` (ADR-031 §13, ADR-033 §6): the author deletes their activity
 * for good (ADR-017) unless the worker is processing it, then its stored files. Not visible:
 * `404`; visible but someone else's: `403`.
 */
@Injectable()
export class DeleteActivityUseCase {
  private readonly logger = new Logger(DeleteActivityUseCase.name);

  constructor(
    private readonly activities: ActivityRepository,
    private readonly imports: ActivityImportRepository,
    private readonly getVisibleActivity: GetVisibleActivityUseCase,
    private readonly storage: StorageService,
    private readonly events: EventEmitter2,
  ) {}

  async execute(userId: string, activityId: string): Promise<void> {
    const activity = await this.getVisibleActivity.execute(userId, activityId);
    if (!activity) {
      // Same code as before ADR-033: the app treats it as already deleted (ADR-031 §14).
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }
    if (activity.userId !== userId) {
      throw new ForbiddenException({
        code: "not_activity_author",
        message: "Only the author can delete this activity",
      });
    }
    // Read before the delete, so nothing after the commit can fail the request.
    const storedKeys = await this.storedKeys(userId, activity.id);
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
    const event: ActivityDeletedEvent = { activityId: activity.id, userId };
    this.events.emit(ACTIVITY_DELETED_EVENT, event);
    // The row is gone: files left behind are unreachable, so a failure is only logged.
    await Promise.all(
      storedKeys.map((key) =>
        this.storage.deleteObject(key).catch((error: unknown) => {
          this.logger.warn(`${key} of deleted activity ${activity.id} not removed: ${String(error)}`);
        }),
      ),
    );
  }

  /** The trace and, for an imported activity, the original file (the import id is the activity id, ADR-028 §1). */
  private async storedKeys(userId: string, activityId: string): Promise<string[]> {
    const keys = [activityTraceKey(userId, activityId)];
    const activityImport = await this.imports.findById(activityId);
    if (activityImport?.userId === userId) {
      keys.push(activityImportSourceKey(userId, activityId, activityImport.format));
    }
    return keys;
  }
}
