import { Injectable } from "@nestjs/common";
import type { FeedAuthor } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { UsersService } from "@repo/core/users";

/** How an athlete is shown next to their content: Activity author, comment author, kudos giver. */
export type AthleteIdentity = FeedAuthor;

/**
 * Assembles athlete identities for every list of the API (ADR-029 §2:
 * modules return user ids only; names live in `users` and `auth`), with one
 * batch call per module. `user_profile` names and avatar win; Better
 * Auth's account name and image are the fallback.
 */
@Injectable()
export class AthleteIdentities {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
  ) {}

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
        avatarUrl: summary?.avatarUrl ?? identity?.image ?? null,
      };
    };
  }
}
