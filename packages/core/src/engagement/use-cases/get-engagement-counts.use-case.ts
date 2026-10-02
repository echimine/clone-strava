import { Injectable } from "@nestjs/common";
import { KudosRepository } from "../repositories/kudos.repository.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import type { EngagementCounts } from "../domain/engagement-counts.js";

/** Batch read backing `EngagementService.getCounts` (ADR-021 §2 rule 6, §6 feed example). */
@Injectable()
export class GetEngagementCountsUseCase {
  constructor(
    private readonly kudos: KudosRepository,
    private readonly comments: CommentRepository,
  ) {}

  /** One entry per requested id, zeros included. */
  async execute(activityIds: string[]): Promise<Map<string, EngagementCounts>> {
    const ids = [...new Set(activityIds)];
    const [kudos, comments] = await Promise.all([
      this.kudos.countByActivityIds(ids),
      this.comments.countByActivityIds(ids),
    ]);
    return new Map(
      ids.map((id) => [id, { kudosCount: kudos.get(id) ?? 0, commentCount: comments.get(id) ?? 0 }]),
    );
  }
}
