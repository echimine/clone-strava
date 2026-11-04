import { Inject, Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { UpdateProfileRequest } from "@repo/contracts";
import { DATABASE, type Database } from "../../infrastructure/index.js";
import type { ActiveSportCatalog } from "../domain/active-sport-catalog.js";
import { isOldEnough, MINIMUM_AGE_YEARS } from "../domain/onboarding-answers.js";
import { profileFieldsOf, withMainSport } from "../domain/profile-details.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";
import { UserSportRepository } from "../repositories/user-sport.repository.js";

/** No birth date before this day: catches a mistyped year. */
const EARLIEST_BIRTH_DATE = "1900-01-01";

/**
 * "Modifier le profil" (ADR-036 §3), in one transaction: creates the `user_profile` row if needed,
 * writes the fields sent (an empty Bio, Ville or Pays clears it), and puts `mainSportCode` first
 * in the Practiced sports. Better Auth's `user.name` is the caller's job (`auth` is another module).
 */
@Injectable()
export class UpdateProfileUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly profiles: UserProfileRepository,
    private readonly sports: UserSportRepository,
  ) {}

  /** `422` under {@link MINIMUM_AGE_YEARS} (UTC day) or for an unknown or inactive sport. */
  async execute(
    userId: string,
    request: UpdateProfileRequest,
    sportCatalog: ActiveSportCatalog,
    now = new Date(),
  ): Promise<void> {
    const { birthDate, mainSportCode } = request;
    if (birthDate !== undefined) {
      if (birthDate < EARLIEST_BIRTH_DATE) {
        throw invalid("birthDate", `The birth date must be on or after ${EARLIEST_BIRTH_DATE}`);
      }
      if (!isOldEnough(birthDate, now.toISOString().slice(0, 10))) {
        throw invalid("birthDate", `The athlete must be at least ${MINIMUM_AGE_YEARS} years old`);
      }
    }
    if (mainSportCode !== undefined && !(await sportCatalog.activeCodes()).has(mainSportCode)) {
      throw invalid("mainSportCode", "Unknown or inactive sport type");
    }

    await this.db.transaction(async (tx) => {
      await this.profiles.upsert(userId, profileFieldsOf(request), tx);
      if (mainSportCode !== undefined) {
        const current = await this.sports.findCodes(userId, tx);
        const reordered = withMainSport(current, mainSportCode);
        if (reordered !== current) {
          await this.sports.replaceAll(userId, reordered, tx);
        }
      }
    });
  }
}

function invalid(field: string, message: string): UnprocessableEntityException {
  return new UnprocessableEntityException({ code: "validation_error", message, details: [{ field, message }] });
}
