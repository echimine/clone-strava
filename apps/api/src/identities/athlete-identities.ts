import { Injectable, NotFoundException } from "@nestjs/common";
import type { FeedAuthor } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { UsersService } from "@repo/core/users";

/** How an athlete is shown next to their content: Activity author, comment author, kudos giver. */
export type AthleteIdentity = FeedAuthor;

/**
 * Assembles athlete identities for every list of the API (ADR-029 §2:
 * modules return user ids only; names live in `users` and `auth`), with one
 * batch call per module. `user_profile` names win over Better Auth's
 * account name; the avatar is still Better Auth's image.
 */
@Injectable()
export class AthleteIdentities {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
  ) {}

  /**
   * `404 athlete_not_found` unless `userId` is an athlete (ADR-036 §1, §3):
   * athletes are Better Auth `user` rows, which `auth` owns.
   */
  async assertExists(userId: string): Promise<void> {
    const [known] = await this.auth.getPublicIdentities([userId]);
    if (!known) {
      throw new NotFoundException({ code: "athlete_not_found", message: "Athlete not found" });
    }
  }

  /** Resolves `userIds` at once; the returned lookup answers for any of them. */
  async resolve(userIds: string[]): Promise<(userId: string) => AthleteIdentity> {
    const ids = [...new Set(userIds)];
    if (ids.length === 0) {
      return (userId) => ({ id: userId, displayName: "", avatarUrl: null });
    }
    const [summaries, identities] = await Promise.all([
      this.users.getSummaries(ids),
      this.auth.getPublicIdentities(ids),
    ]);
    const summaryById = new Map(summaries.map((summary) => [summary.userId, summary]));
    const identityById = new Map(identities.map((identity) => [identity.userId, identity]));

    return (userId) => {
      const summary = summaryById.get(userId);
      const identity = identityById.get(userId);
      const profileName = [summary?.firstName, summary?.lastName].filter(Boolean).join(" ").trim();
      return {
        id: userId,
        displayName: profileName || identity?.name || "",
        // `avatar_url` was never written, so the Better Auth image was all the app ever saw.
        // The signed `avatarKey` replaces it with the Avatar API (ADR-037 §2).
        avatarUrl: identity?.image ?? null,
      };
    };
  }
}
