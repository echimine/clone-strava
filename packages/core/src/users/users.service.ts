import { Injectable } from "@nestjs/common";
import { GetUserSummariesUseCase } from "./use-cases/get-user-summaries.use-case.js";
import type { UserSummary } from "./domain/user-summary.js";

/**
 * Public facade of the `users` module (ADR-021 §1: layer 0, no dependency
 * on other domain modules). The only class other modules and apps call.
 */
@Injectable()
export class UsersService {
  constructor(private readonly getUserSummaries: GetUserSummariesUseCase) {}

  /** Batch read (ADR-021 §2 rule 6), e.g. for feed authors or a profile screen. */
  getSummaries(userIds: string[]): Promise<UserSummary[]> {
    return this.getUserSummaries.execute(userIds);
  }

  /** Convenience single-id read (e.g. `GET /v1/me`), built on the batch call above. */
  async getSummary(userId: string): Promise<UserSummary | undefined> {
    const [summary] = await this.getSummaries([userId]);
    return summary;
  }
}
