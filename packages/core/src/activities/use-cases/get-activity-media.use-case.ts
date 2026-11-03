import { Injectable } from "@nestjs/common";
import type { ActivityMediaRecord } from "../domain/activity-media.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";

/**
 * Batch read of the Media of several Activities (ADR-021 §2 rule 6, ADR-037 §7): one query per
 * page whatever its size. Every requested id gets an entry, `[]` without Media. Visibility is the
 * caller's: it passes only Activities the viewer may see.
 */
@Injectable()
export class GetActivityMediaUseCase {
  constructor(private readonly media: ActivityMediaRepository) {}

  async execute(activityIds: string[]): Promise<Map<string, ActivityMediaRecord[]>> {
    const ids = [...new Set(activityIds)];
    const byActivity = new Map<string, ActivityMediaRecord[]>(ids.map((id) => [id, []]));
    for (const record of await this.media.findByActivityIds(ids)) {
      byActivity.get(record.activityId)?.push(record);
    }
    return byActivity;
  }
}
