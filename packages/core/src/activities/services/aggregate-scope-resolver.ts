import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { Visibility } from "@repo/contracts";
import { SocialService } from "../../social/index.js";
import { SportsService } from "../../sports/index.js";
import type { AggregateScope } from "../repositories/activity-aggregate.repository.js";

/**
 * Which of an athlete's Activities count in a viewer's figures (ADR-036 §3): the owner counts all
 * of theirs; others `public`, plus `followers` when they follow the athlete (accepted); never
 * `private`, so nothing leaks through an aggregate. Only processed Activities are aggregated.
 */
@Injectable()
export class AggregateScopeResolver {
  constructor(
    private readonly social: SocialService,
    private readonly sports: SportsService,
  ) {}

  /** `422 validation_error` for an unknown or inactive `sportTypeCode`. */
  async resolve(viewerId: string, athleteId: string, sportTypeCode?: string): Promise<AggregateScope> {
    const [visibilities] = await Promise.all([
      this.visibilities(viewerId, athleteId),
      sportTypeCode === undefined ? undefined : this.assertActiveSport(sportTypeCode),
    ]);
    return { userId: athleteId, visibilities, sportTypeCode };
  }

  private async visibilities(viewerId: string, athleteId: string): Promise<Visibility[]> {
    if (viewerId === athleteId) {
      return ["public", "followers", "private"];
    }
    const followees = await this.social.getFolloweeIds(viewerId);
    return followees.includes(athleteId) ? ["public", "followers"] : ["public"];
  }

  private async assertActiveSport(code: string): Promise<void> {
    const sport = await this.sports.findByCode(code);
    if (!sport || !sport.isActive) {
      const message = "Unknown or inactive sport type";
      throw new UnprocessableEntityException({
        code: "validation_error",
        message,
        details: [{ field: "sport", message }],
      });
    }
  }
}
