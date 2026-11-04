import { Injectable, NotFoundException } from "@nestjs/common";
import type { ActivityLabel } from "../domain/admin-activity.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { MediaRemover } from "../services/media-remover.js";

/**
 * « Retirer un Média » (`DELETE /v1/admin/activities/:id/media/:mediaId`, ADR-038 §11): the
 * author's delete path ({@link MediaRemover}) without the author check, as a Sanction.
 * `404 media_not_found` unless the Activity has that Media, so nothing is recorded nor sent for
 * a Media already gone. Returns its Activity, for the e-mail to the athlete.
 */
@Injectable()
export class RemoveMediaAsSanctionUseCase {
  constructor(
    private readonly adminActivities: AdminActivityRepository,
    private readonly media: ActivityMediaRepository,
    private readonly remover: MediaRemover,
  ) {}

  async execute(activityId: string, mediaId: string): Promise<ActivityLabel> {
    const [label] = await this.adminActivities.findLabels([activityId]);
    if (!label) {
      throw activityNotFound();
    }
    const media = await this.media.findById(mediaId);
    if (media?.activityId !== label.id || !(await this.remover.remove(label, mediaId, { bySanction: true }))) {
      throw new NotFoundException({ code: "media_not_found", message: "Media not found" });
    }
    return label;
  }
}
