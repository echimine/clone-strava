import { Injectable } from "@nestjs/common";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { AddCommentUseCase } from "./use-cases/add-comment.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import { KudosRepository } from "./repositories/kudos.repository.js";
import type { EngagementCounts } from "./domain/engagement-counts.js";
import type { KudosState } from "./domain/kudos-state.js";

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
    private readonly kudos: KudosRepository,
  ) {}

  giveKudos(userId: string, activityId: string): Promise<KudosState> {
    return this.giveKudosUseCase.execute(userId, activityId);
  }

  removeKudos(userId: string, activityId: string): Promise<KudosState> {
    return this.giveKudosUseCase.remove(userId, activityId);
  }

  /** Batch read (ADR-029): which of `activityIds` the viewer gave kudos to. */
  getKudoedBy(userId: string, activityIds: string[]): Promise<Set<string>> {
    return this.kudos.findKudoedActivityIds(userId, activityIds);
  }

  addComment(userId: string, activityId: string, body: string): Promise<void> {
    return this.addCommentUseCase.execute(userId, activityId, body);
  }

  /** Batch read (ADR-021 §2 rule 6): used by list screens (feed step 4). */
  getCounts(activityIds: string[]): Promise<Map<string, EngagementCounts>> {
    return this.getEngagementCountsUseCase.execute(activityIds);
  }
}
