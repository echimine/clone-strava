import { Injectable, NotFoundException } from "@nestjs/common";
import { AuthUserRepository } from "../repositories/auth-user.repository.js";

/** An account as the backoffice actions read it, or `404 user_not_found`. */
@Injectable()
export class AccountReader {
  constructor(private readonly users: AuthUserRepository) {}

  async get(userId: string) {
    const account = await this.users.findAccount(userId);
    if (!account) {
      throw new NotFoundException({ code: "user_not_found", message: "User not found" });
    }
    return account;
  }
}
