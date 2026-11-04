import { Injectable } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { ACTIVITY_UPDATED_EVENT, type ActivityUpdatedEvent } from "@repo/contracts";
import type { ActivityLabel } from "../domain/admin-activity.js";
import { defaultActivityTitle } from "../domain/import/default-title.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";

/** What a reset leaves, and the Activity as the athlete knew it (for the e-mail). */
export interface ActivityTextReset {
  previous: ActivityLabel;
  title: string;
  description: null;
}

/**
 * « Réinitialiser titre et description » (`POST /v1/admin/activities/:id/reset-text`,
 * ADR-038 §11), a Sanction: the default title of its sport and start time
 * (`defaultActivityTitle`), no description, whatever the processing state. The author's other
 * devices refresh through `activities.activity.updated`.
 */
@Injectable()
export class ResetActivityTextUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly adminActivities: AdminActivityRepository,
    private readonly events: EventEmitter2,
  ) {}

  async execute(activityId: string): Promise<ActivityTextReset> {
    const row = await this.activities.findById(activityId);
    if (!row) {
      throw activityNotFound();
    }
    const text = { title: defaultActivityTitle(row.sportTypeCode, row.startedAt), description: null };
    if (!(await this.adminActivities.replaceText(row.id, text))) {
      throw activityNotFound();
    }
    // After the commit (ADR-021 §3).
    const event: ActivityUpdatedEvent = {
      activityId: row.id,
      userId: row.userId,
      changedFields: ["title", "description"],
    };
    this.events.emit(ACTIVITY_UPDATED_EVENT, event);
    return {
      previous: { id: row.id, userId: row.userId, title: row.title, startedAt: row.startedAt },
      ...text,
    };
  }
}
