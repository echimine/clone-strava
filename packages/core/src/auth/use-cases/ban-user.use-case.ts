import { ConflictException, Injectable } from "@nestjs/common";
import { ADMIN_USER_ERROR_CODES } from "@repo/contracts";
import { activeBan, type ActiveBan } from "../domain/ban.js";
import { AuthAdminApi } from "../services/auth-admin-api.js";
import { AccountReader } from "../services/account-reader.js";

/**
 * Bans an athlete (ADR-038 §5, §6) through the admin plugin, which also revokes every session.
 * Banning again replaces the duration. An Administrator is never banned: `409 user_is_admin`.
 * Returns the Ban now in force.
 */
@Injectable()
export class BanUserUseCase {
  constructor(
    private readonly accounts: AccountReader,
    private readonly api: AuthAdminApi,
  ) {}

  async execute(headers: Headers, userId: string, reason: string, expiresInSeconds: number | null): Promise<ActiveBan> {
    const account = await this.accounts.get(userId);
    if (account.role === "admin") {
      throw new ConflictException({
        code: ADMIN_USER_ERROR_CODES.userIsAdmin,
        message: "An Administrator cannot be banned before being demoted",
      });
    }
    await this.api.ban(headers, userId, reason, expiresInSeconds);
    const banned = await this.accounts.get(userId);
    const ban = activeBan(banned, new Date());
    if (!ban) {
      throw new Error(`Ban of ${userId} not in force right after banUser`);
    }
    return ban;
  }
}
