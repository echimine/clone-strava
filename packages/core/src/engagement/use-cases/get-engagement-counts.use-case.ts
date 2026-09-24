import { Injectable, NotImplementedException } from "@nestjs/common";
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

  async execute(_activityIds: string[]): Promise<Map<string, EngagementCounts>> {
    throw new NotImplementedException();
  }
}
