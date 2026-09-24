import { Injectable, NotImplementedException } from "@nestjs/common";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import type { UserSummary } from "../domain/user-summary.js";

/**
 * Batch read backing `UsersService.getSummaries` (ADR-021 §2 rule 6, §6
 * "List screens compose batch calls"): one query for any number of ids.
 */
@Injectable()
export class GetUserSummariesUseCase {
  constructor(private readonly userProfiles: UserProfileRepository) {}

  async execute(_userIds: string[]): Promise<UserSummary[]> {
    throw new NotImplementedException();
  }
}
