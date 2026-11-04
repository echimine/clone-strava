import { Injectable } from "@nestjs/common";
import { BanRepository } from "./repositories/ban.repository.js";

/**
 * The `auth` module's Ban reads for the viewer filter (ADR-038 §6, §7): who is hidden from
 * everyone while their Ban lasts. Kept apart from `AuthService` because it needs no Better Auth
 * instance, only the database: every module with a read path can import `BansModule`.
 */
@Injectable()
export class BansService {
  constructor(private readonly bans: BanRepository) {}

  /** Ids of the actively banned athletes; a Ban whose end has passed is over without a sign-in. */
  activelyBannedUserIds(now = new Date()): Promise<string[]> {
    return this.bans.findActivelyBannedIds(now);
  }
}
