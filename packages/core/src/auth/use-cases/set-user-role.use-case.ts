import { ConflictException, Injectable } from "@nestjs/common";
import { ADMIN_USER_ERROR_CODES, type UserRole } from "@repo/contracts";
import { AuthAdminStatsRepository } from "../repositories/auth-admin-stats.repository.js";
import { AuthAdminApi } from "../services/auth-admin-api.js";
import { AccountReader } from "../services/account-reader.js";

/**
 * Grants or removes the `admin` role from the backoffice (ADR-038 §5) through the admin plugin.
 * `409 role_unchanged` when the account already has it; nobody demotes themself
 * (`cannot_demote_self`) nor the last Administrator (`last_admin`). A promoted account sets up
 * its 2FA at its first backoffice sign-in (`AdminGuard`).
 */
@Injectable()
export class SetUserRoleUseCase {
  constructor(
    private readonly accounts: AccountReader,
    private readonly admins: AuthAdminStatsRepository,
    private readonly api: AuthAdminApi,
  ) {}

  async execute(headers: Headers, actorId: string, userId: string, role: UserRole): Promise<void> {
    const account = await this.accounts.get(userId);
    if (account.role === role) {
      throw new ConflictException({ code: ADMIN_USER_ERROR_CODES.roleUnchanged, message: `The account is already ${role}` });
    }
    if (role === "user") {
      if (userId === actorId) {
        throw new ConflictException({
          code: ADMIN_USER_ERROR_CODES.cannotDemoteSelf,
          message: "An Administrator cannot demote themself",
        });
      }
      if ((await this.admins.findAdminIds()).length <= 1) {
        throw new ConflictException({
          code: ADMIN_USER_ERROR_CODES.lastAdmin,
          message: "The last Administrator cannot be demoted",
        });
      }
    }
    await this.api.setRole(headers, userId, role);
  }
}
