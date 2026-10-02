import { Injectable } from "@nestjs/common";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import type { UserSummary } from "./domain/user-summary.js";
import { UserProfileRepository } from "./repositories/user-profile.repository.js";
import {
  DEFAULT_USER_ACTIVITY_DEFAULTS,
  type UserActivityDefaults,
} from "./domain/activity-defaults.js";

/**
 * Public facade of the `users` module (ADR-021 §1: layer 0, no dependency
 * on other domain modules). The only class other modules and apps call.
 */
@Injectable()
export class UsersService {
  constructor(
    private readonly getUserSummaries: GetUserSummariesUseCase,
    private readonly userProfiles: UserProfileRepository,
  ) {}

  /** Batch read (ADR-021 §2 rule 6), e.g. for feed authors or a profile screen. */
  getSummaries(userIds: string[]): Promise<UserSummary[]> {
    return this.getUserSummaries.execute(userIds);
  }

  /** Convenience single-id read (e.g. `GET /v1/me`), built on the batch call above. */
  async getSummary(userId: string): Promise<UserSummary | undefined> {
    const [summary] = await this.getSummaries([userId]);
    return summary;
  }

  /** Default visibility and privacy zone radius for a new activity. */
  async getActivityDefaults(userId: string): Promise<UserActivityDefaults> {
    const profile = await this.userProfiles.findById(userId);
    if (!profile) {
      return DEFAULT_USER_ACTIVITY_DEFAULTS;
    }
    return {
      defaultVisibility: profile.defaultVisibility,
      privacyZoneRadiusM: profile.privacyZoneRadiusM,
    };
  }
}
