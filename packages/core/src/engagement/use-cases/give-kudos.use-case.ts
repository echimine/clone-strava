import { Injectable, NotImplementedException } from "@nestjs/common";
import { KudosRepository } from "../repositories/kudos.repository.js";

/**
 * Gives kudos on an activity (ADR-017). Checks the target activity exists
 * and is visible to the user through `ActivitiesService` (ADR-021 §2:
 * `engagement` may depend on `activities`), never a direct table read.
 */
@Injectable()
export class GiveKudosUseCase {
  constructor(private readonly kudos: KudosRepository) {}

  async execute(_userId: string, _activityId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
