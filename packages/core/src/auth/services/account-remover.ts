import { BadRequestException, ConflictException, Inject, Injectable } from "@nestjs/common";
import { ACCOUNT_DELETION_ERROR_CODES, ADMIN_USER_ERROR_CODES } from "@repo/contracts";
import { isAPIError } from "better-auth/api";
import { AUTH_INSTANCE } from "../auth.constants.js";
import type { AuthInstance } from "../auth-instance.type.js";
import { AuthAdminApi } from "./auth-admin-api.js";
import { AccountReader } from "./account-reader.js";

/** The Sign-in code's identifier in `verification`, as the email OTP plugin writes it. */
const signInCodeIdentifier = (email: string) => `sign-in-otp-${email.toLowerCase()}`;

/** Better Auth's email OTP error codes → ours, all `400` (ask for a new code). */
const CODE_ERRORS: Record<string, string> = {
  INVALID_OTP: ACCOUNT_DELETION_ERROR_CODES.invalidCode,
  OTP_EXPIRED: ACCOUNT_DELETION_ERROR_CODES.codeExpired,
  TOO_MANY_ATTEMPTS: ACCOUNT_DELETION_ERROR_CODES.tooManyAttempts,
};

/**
 * Deletes accounts (ADR-038 §13): sessions revoked, then the `user` row, whose SQL cascade erases
 * everything else. The athlete re-verifies with a Sign-in code (email OTP plugin, type
 * `sign-in`); an Administrator goes through the admin plugin's `removeUser`.
 */
@Injectable()
export class AccountRemover {
  constructor(
    @Inject(AUTH_INSTANCE) private readonly auth: AuthInstance,
    private readonly accounts: AccountReader,
    private readonly adminApi: AuthAdminApi,
  ) {}

  /** Sends a Sign-in code to the account's address (Google accounts included). */
  async sendCode(email: string): Promise<void> {
    await this.auth.api.sendVerificationOTP({ body: { email, type: "sign-in" } });
  }

  /** Checks the code, then spends it; `400 invalid_code` / `code_expired` / `too_many_attempts`. */
  async checkCode(email: string, code: string): Promise<void> {
    try {
      await this.auth.api.checkVerificationOTP({ body: { email, type: "sign-in", otp: code } });
    } catch (error) {
      if (isAPIError(error)) {
        const raw = (error.body as { code?: unknown } | undefined)?.code;
        const code = (typeof raw === "string" && CODE_ERRORS[raw]) || ACCOUNT_DELETION_ERROR_CODES.invalidCode;
        throw new BadRequestException({ code, message: "Code invalide ou expiré" });
      }
      throw error;
    }
    const context = await this.auth.$context;
    await context.internalAdapter.deleteVerificationByIdentifier(signInCodeIdentifier(email));
  }

  /** The athlete deletes their own account: no admin session, so through the internal adapter. */
  async removeOwn(userId: string): Promise<void> {
    const context = await this.auth.$context;
    await context.internalAdapter.deleteUserSessions(userId);
    await context.internalAdapter.deleteUser(userId);
  }

  /**
   * An Administrator deletes an athlete's account (`removeUser`, with their headers). `404
   * user_not_found`; `409 user_is_admin` for an Administrator, who must be demoted first.
   */
  async removeAsAdmin(headers: Headers, userId: string): Promise<void> {
    const account = await this.accounts.get(userId);
    if (account.role === "admin") {
      throw new ConflictException({
        code: ADMIN_USER_ERROR_CODES.userIsAdmin,
        message: "An Administrator's account cannot be deleted before being demoted",
      });
    }
    await this.adminApi.remove(headers, userId);
  }
}
