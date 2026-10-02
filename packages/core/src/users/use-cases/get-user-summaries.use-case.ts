import { Injectable } from "@nestjs/common";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import type { UserSummary } from "../domain/user-summary.js";

/**
 * Batch read backing `UsersService.getSummaries` (ADR-021 §2 rule 6, §6
 * "List screens compose batch calls"): one query for any number of ids.
 */
@Injectable()
export class GetUserSummariesUseCase {
  constructor(private readonly userProfiles: UserProfileRepository) {}

  /** One summary per requested id; users without a profile row get null fields. */
  async execute(userIds: string[]): Promise<UserSummary[]> {
    const ids = [...new Set(userIds)];
    const profiles = new Map((await this.userProfiles.findByIds(ids)).map((p) => [p.userId, p]));
    return ids.map((userId) => {
      const profile = profiles.get(userId);
      return {
        userId,
        firstName: profile?.firstName ?? null,
        lastName: profile?.lastName ?? null,
        avatarUrl: profile?.avatarUrl ?? null,
      };
    });
  }
}
