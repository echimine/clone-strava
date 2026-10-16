import { Injectable } from "@nestjs/common";
import { SocialService } from "../../social/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { toActivityRecord, type ActivityRecord } from "../domain/activity-record.js";

/**
 * An activity as seen by a viewer (ADR-029, ADR-017 visibility): the owner
 * sees everything; others see processed `public` activities, and
 * `followers` ones when they follow the owner. `null` otherwise, so callers
 * answer 404 without revealing that the activity exists.
 */
@Injectable()
export class GetVisibleActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly social: SocialService,
  ) {}

  async execute(viewerId: string, activityId: string): Promise<ActivityRecord | null> {
    const row = await this.findRow(viewerId, activityId);
    return row ? toActivityRecord(row) : null;
  }

  /** The full `activity` row under the same rules, for this module's own use cases (ADR-033 §2). */
  async findRow(viewerId: string, activityId: string) {
    const row = await this.activities.findById(activityId);
    if (!row) {
      return null;
    }
    if (row.userId === viewerId) {
      return row;
    }
    if (row.processingStatus !== "processed" || row.visibility === "private") {
      return null;
    }
    if (row.visibility === "followers") {
      const followees = await this.social.getFolloweeIds(viewerId);
      return followees.includes(row.userId) ? row : null;
    }
    return row;
  }
}
