import { Injectable } from "@nestjs/common";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { AddCommentUseCase } from "./use-cases/add-comment.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import type { EngagementCounts } from "./domain/engagement-counts.js";

/**
 * Public facade of the `engagement` module (ADR-021 §1: layer 3, may
 * depend on `activities`, `social`, `users`).
 */
@Injectable()
export class EngagementService {
  constructor(
    private readonly giveKudosUseCase: GiveKudosUseCase,
    private readonly addCommentUseCase: AddCommentUseCase,
    private readonly getEngagementCountsUseCase: GetEngagementCountsUseCase,
  ) {}

  giveKudos(userId: string, activityId: string): Promise<void> {
    return this.giveKudosUseCase.execute(userId, activityId);
  }

  addComment(userId: string, activityId: string, body: string): Promise<void> {
    return this.addCommentUseCase.execute(userId, activityId, body);
  }

  /** Batch read (ADR-021 §2 rule 6): used by list screens (feed step 4). */
  getCounts(activityIds: string[]): Promise<Map<string, EngagementCounts>> {
    return this.getEngagementCountsUseCase.execute(activityIds);
  }
}
