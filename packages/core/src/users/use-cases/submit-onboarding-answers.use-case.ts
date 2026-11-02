import { Inject, Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { OnboardingAnswersRequest } from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import { emptyFieldsFilledBy, isOldEnough, MINIMUM_AGE_YEARS } from "../domain/onboarding-answers.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { UserSportRepository } from "../repositories/user-sport.repository.js";

/**
 * The Onboarding answers become the profile (ADR-035 §4, §5), in one
 * transaction: creates the `user_profile` row if needed, fills only the
 * fields that are still `null`, and writes the sports only if the athlete
 * has none. `user.name` is never touched. Sport codes are checked by the
 * caller against `sports` (ADR-021 §2: `users` depends on no module).
 */
@Injectable()
export class SubmitOnboardingAnswersUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly profiles: UserProfileRepository,
    private readonly sports: UserSportRepository,
  ) {}

  /** `true` if anything was filled. `422` under {@link MINIMUM_AGE_YEARS} (UTC day). */
  async execute(userId: string, answers: OnboardingAnswersRequest, now = new Date()): Promise<boolean> {
    if (!isOldEnough(answers.birthDate, now.toISOString().slice(0, 10))) {
      const message = `The athlete must be at least ${MINIMUM_AGE_YEARS} years old`;
      throw new UnprocessableEntityException({
        code: "validation_error",
        message,
        details: [{ field: "birthDate", message }],
      });
    }

    return this.db.transaction(async (tx) => {
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
  }
}
