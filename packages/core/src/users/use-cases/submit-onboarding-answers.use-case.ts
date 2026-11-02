import { Inject, Injectable, UnprocessableEntityException } from "@nestjs/common";
import { ANALYTICS_EVENTS, type OnboardingAnswersRequest } from "@repo/contracts";
import { AnalyticsService } from "../../analytics/index.js";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import type { ActiveSportCatalog } from "../domain/active-sport-catalog.js";
import { emptyFieldsFilledBy, isOldEnough, MINIMUM_AGE_YEARS } from "../domain/onboarding-answers.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { UserSportRepository } from "../repositories/user-sport.repository.js";

/**
 * The Onboarding answers become the profile (ADR-035 §4, §5), in one
 * transaction: creates the `user_profile` row if needed, fills only the
 * fields that are still `null`, and writes the sports only if the athlete
 * has none. `user.name` is never touched. The active sport codes come from
 * the caller's {@link ActiveSportCatalog} (ADR-021 §2: `users` depends on no
 * module). `onboarding_answers_received` is sent after the commit, only when
 * something was filled (ADR-035 §8, ADR-021 §2 rule 4).
 */
@Injectable()
export class SubmitOnboardingAnswersUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly profiles: UserProfileRepository,
    private readonly sports: UserSportRepository,
    private readonly analytics: AnalyticsService,
  ) {}

  /** `422` under {@link MINIMUM_AGE_YEARS} (UTC day) or for an unknown or inactive sport. */
  async execute(
    userId: string,
    answers: OnboardingAnswersRequest,
    sportCatalog: ActiveSportCatalog,
    now = new Date(),
  ): Promise<void> {
    if (!isOldEnough(answers.birthDate, now.toISOString().slice(0, 10))) {
      throw invalid("birthDate", `The athlete must be at least ${MINIMUM_AGE_YEARS} years old`);
    }
    const activeCodes = await sportCatalog.activeCodes();
    if (!answers.sportCodes.every((code) => activeCodes.has(code))) {
      throw invalid("sportCodes", "Unknown or inactive sport type");
    }

    const filled = await this.db.transaction(async (tx) => {
      await this.profiles.insertIfAbsent(userId, tx);
      const patch = emptyFieldsFilledBy(await this.profiles.lockOnboardingFields(userId, tx), answers);
      const profileFilled = Object.keys(patch).length > 0;
      if (profileFilled) {
        await this.profiles.update(userId, patch, tx);
      }
      const sportsFilled = !(await this.sports.hasAny(userId, tx));
      if (sportsFilled) {
        await this.sports.insertAll(userId, answers.sportCodes, tx);
      }
      return profileFilled || sportsFilled;
    });
    if (filled) {
      this.analytics.capture(ANALYTICS_EVENTS.ONBOARDING_ANSWERS_RECEIVED, userId, {});
    }
  }
}

function invalid(field: string, message: string): UnprocessableEntityException {
  return new UnprocessableEntityException({ code: "validation_error", message, details: [{ field, message }] });
}
