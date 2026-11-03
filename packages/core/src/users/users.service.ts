import { Injectable } from "@nestjs/common";
import type { OnboardingAnswersRequest } from "@repo/contracts";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import { SearchUsersByNameUseCase } from "./use-cases/search-users-by-name.use-case.js";
import { SubmitOnboardingAnswersUseCase } from "./use-cases/submit-onboarding-answers.use-case.js";
import type { ActiveSportCatalog } from "./domain/active-sport-catalog.js";
import type { UserSummary } from "./domain/user-summary.js";
import { UserProfileRepository } from "./repositories/user-profile.repository.js";
import { UserSportRepository } from "./repositories/user-sport.repository.js";
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
    private readonly submitOnboarding: SubmitOnboardingAnswersUseCase,
    private readonly userSports: UserSportRepository,
    private readonly searchUsersByName: SearchUsersByNameUseCase,
  ) {}

  /**
   * Athlete search (ADR-036 §2): ids of at most 20 users whose profile name
   * contains `query` (trimmed, 2 to 50 characters, else `422 invalid_query`),
   * ignoring case and accents, word starts first, `excludeUserId` left out.
   */
  searchByName(query: string | undefined, excludeUserId: string): Promise<string[]> {
    return this.searchUsersByName.execute(query, excludeUserId);
  }

  /** Batch read (ADR-021 §2 rule 6), e.g. for feed authors or a profile screen. */
  getSummaries(userIds: string[]): Promise<UserSummary[]> {
    return this.getUserSummaries.execute(userIds);
  }

  /** Convenience single-id read (e.g. `GET /v1/me`), built on the batch call above. */
  async getSummary(userId: string): Promise<UserSummary | undefined> {
    const [summary] = await this.getSummaries([userId]);
    return summary;
  }

  /** The athlete's Practiced sports in their order (ADR-035 §4, ADR-036 §3); empty if never chosen. */
  getPracticedSports(userId: string): Promise<string[]> {
    return this.userSports.findCodes(userId);
  }

  /**
   * The name everyone sees (ADR-036 §3), already trimmed and validated by the caller. Creates the
   * profile row if needed.
   */
  updateName(userId: string, name: { firstName: string; lastName: string }): Promise<void> {
    return this.userProfiles.upsertName(userId, name);
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

  /**
   * The Onboarding answers fill the empty profile fields (ADR-035 §4, §5).
   * `sportCatalog` says which sport codes are active: `users` depends on no
   * module (ADR-021 §2), so the composing app supplies it.
   */
  submitOnboardingAnswers(
    userId: string,
    answers: OnboardingAnswersRequest,
    sportCatalog: ActiveSportCatalog,
  ): Promise<void> {
    return this.submitOnboarding.execute(userId, answers, sportCatalog);
  }
}
