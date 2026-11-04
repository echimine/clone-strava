import { Injectable } from "@nestjs/common";
import type { ActivityLabel } from "../domain/admin-activity.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { ActivityRemover } from "../services/activity-remover.js";

/**
 * « Supprimer l'Activité » (`DELETE /v1/admin/activities/:id`, ADR-038 §11): the author's delete
 * path ({@link ActivityRemover}) without the author check, as a Sanction; `409 not_deletable`
 * while `processing`. Returns the Activity as it was, for the e-mail to the athlete.
 */
@Injectable()
export class DeleteActivityAsSanctionUseCase {
  constructor(
    private readonly adminActivities: AdminActivityRepository,
    private readonly remover: ActivityRemover,
  ) {}

  async execute(activityId: string): Promise<ActivityLabel> {
    const [label] = await this.adminActivities.findLabels([activityId]);
    if (!label) {
      throw activityNotFound();
    }
    await this.remover.remove(label, { bySanction: true });
    return label;
  }
}
