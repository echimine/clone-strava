import { Injectable } from "@nestjs/common";
import type { ActivityComment } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import type { CommentView } from "@repo/core/engagement";
import { UsersService } from "@repo/core/users";

/**
 * Adds author identities to comments (ADR-034 §3) with one batch call per
 * module, as the feed does (ADR-029 §2): `engagement` returns author ids
 * only, identities live in `users` and `auth`.
 */
@Injectable()
export class CommentAssembler {
  constructor(
    private readonly users: UsersService,
    private readonly auth: AuthService,
  ) {}

  async assembleOne(comment: CommentView): Promise<ActivityComment> {
    const [assembled] = await this.assemble([comment]);
    return assembled!;
  }

  async assemble(comments: CommentView[]): Promise<ActivityComment[]> {
    const authorIds = [...new Set(comments.map((comment) => comment.authorId))];
    if (authorIds.length === 0) {
      return [];
    }
    const [summaries, identities] = await Promise.all([
      this.users.getSummaries(authorIds),
      this.auth.getPublicIdentities(authorIds),
    ]);
    const summaryById = new Map(summaries.map((summary) => [summary.userId, summary]));
    const identityById = new Map(identities.map((identity) => [identity.userId, identity]));

    return comments.map((comment) => {
      const summary = summaryById.get(comment.authorId);
      const identity = identityById.get(comment.authorId);
      // `user_profile` names win; Better Auth's account name is the fallback (as in the feed).
      const profileName = [summary?.firstName, summary?.lastName].filter(Boolean).join(" ").trim();
      return {
        id: comment.id,
        body: comment.body,
        createdAt: comment.createdAt.toISOString(),
        updatedAt: comment.updatedAt?.toISOString() ?? null,
        author: {
          id: comment.authorId,
          displayName: profileName || identity?.name || "",
          avatarUrl: summary?.avatarUrl ?? identity?.image ?? null,
        },
        viewerCanEdit: comment.viewerCanEdit,
        viewerCanDelete: comment.viewerCanDelete,
      };
    });
  }
}
