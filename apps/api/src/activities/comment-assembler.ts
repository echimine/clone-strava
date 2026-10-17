import { Injectable } from "@nestjs/common";
import type { ActivityComment } from "@repo/contracts";
import type { CommentView } from "@repo/core/engagement";
import { AthleteIdentities } from "../identities/athlete-identities.js";

/**
 * Adds author identities to comments (ADR-034 §3), as the feed does
 * (ADR-029 §2): `engagement` returns author ids only.
 */
@Injectable()
export class CommentAssembler {
  constructor(private readonly identities: AthleteIdentities) {}

  async assembleOne(comment: CommentView): Promise<ActivityComment> {
    const [assembled] = await this.assemble([comment]);
    return assembled!;
  }

  async assemble(comments: CommentView[]): Promise<ActivityComment[]> {
    const author = await this.identities.resolve(comments.map((comment) => comment.authorId));
    return comments.map((comment) => ({
      id: comment.id,
      body: comment.body,
      createdAt: comment.createdAt.toISOString(),
      updatedAt: comment.updatedAt?.toISOString() ?? null,
      author: author(comment.authorId),
      viewerCanEdit: comment.viewerCanEdit,
      viewerCanDelete: comment.viewerCanDelete,
    }));
  }
}
