import { Injectable } from "@nestjs/common";
import { ActivityAggregateRepository } from "../repositories/activity-aggregate.repository.js";
import { AggregateScopeResolver } from "../services/aggregate-scope-resolver.js";
import { streakWeeks } from "../domain/streak.js";

/** The figures of a profile header that come from Activities (ADR-036 §3). */
export interface AthleteProfileFigures {
  activityCount: number;
  /** All sports (ADR-036 §4). */
  streakWeeks: number;
  /** The sports of those Activities, most Activities first (ties by sport code). */
  sportActivityCounts: { sportTypeCode: string; activityCount: number }[];
}

/**
 * Activity count, Streak and sports of an athlete's profile, over the processed Activities the
 * viewer may see only (ADR-036 §3): nothing about a private Activity leaks through them.
 */
@Injectable()
export class GetAthleteProfileFiguresUseCase {
  constructor(
    private readonly scopes: AggregateScopeResolver,
    private readonly aggregates: ActivityAggregateRepository,
  ) {}

  async execute(viewerId: string, athleteId: string, now = new Date()): Promise<AthleteProfileFigures> {
    const scope = await this.scopes.resolve(viewerId, athleteId);
    const [weekStarts, sportActivityCounts] = await Promise.all([
      this.aggregates.findActiveWeekStarts(scope),
      this.aggregates.findCountsBySport(scope),
    ]);
    return {
      activityCount: sportActivityCounts.reduce((total, sport) => total + sport.activityCount, 0),
      streakWeeks: streakWeeks(weekStarts, now),
      sportActivityCounts,
    };
  }
}
