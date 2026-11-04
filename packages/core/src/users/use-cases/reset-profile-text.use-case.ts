import { Injectable } from "@nestjs/common";
import { RESET_FIRST_NAME } from "../domain/admin-user.js";
import { UserProfileRepository } from "../repositories/user-profile.repository.js";

/**
 * Sanctions on an athlete's profile texts (ADR-038 §5), without free input: the name becomes
 * first name « Athlète » with an empty last name; the bio is emptied. The athlete can change
 * them again. The caller keeps Better Auth's `user.name` in step (`AuthService.setName`).
 */
@Injectable()
export class ResetProfileTextUseCase {
  constructor(private readonly profiles: UserProfileRepository) {}

  /** Returns the account name to set: « Athlète ». */
  async resetName(userId: string): Promise<string> {
    await this.profiles.insertIfAbsent(userId);
    await this.profiles.update(userId, { firstName: RESET_FIRST_NAME, lastName: "" });
    return RESET_FIRST_NAME;
  }

  async resetBio(userId: string): Promise<void> {
    await this.profiles.insertIfAbsent(userId);
    await this.profiles.clearBio(userId);
  }
}
