import { Injectable, NotImplementedException } from "@nestjs/common";
import { ActivityRepository } from "../repositories/activity.repository.js";
import type { ActivityRecord } from "../domain/activity-record.js";

/**
 * Batch read backing `ActivitiesService.getMany` (ADR-021 §2 rule 6, §6):
 * used by `engagement`/`segments` and list screens (feed step 2).
 */
@Injectable()
export class GetActivitiesUseCase {
  constructor(private readonly activities: ActivityRepository) {}

  async execute(_ids: string[]): Promise<ActivityRecord[]> {
    throw new NotImplementedException();
  }
}
