import { Injectable } from "@nestjs/common";
import type { ProgressResponse } from "@repo/contracts";
import { ActivityAggregateRepository } from "../repositories/activity-aggregate.repository.js";
import { AggregateScopeResolver } from "../services/aggregate-scope-resolver.js";
import { addDays, athleteLocalDate, athleteWeekStart, zeroFilledWeeks } from "../domain/athlete-weeks.js";
import { streakWeeks } from "../domain/streak.js";

export const PROGRESS_WEEK_COUNT = 12;

/**
 * The athlete's own Progrès for one sport (ADR-036 §4): the 12 weeks ending with the current one,
 * zero-filled, and the sport's Streak with the current month's active days.
 */
@Injectable()
export class GetProgressUseCase {
  constructor(
    private readonly scopes: AggregateScopeResolver,
    private readonly aggregates: ActivityAggregateRepository,
  ) {}

  async execute(userId: string, sportTypeCode: string, now = new Date()): Promise<ProgressResponse> {
    const scope = await this.scopes.resolve(userId, userId, sportTypeCode);
    const firstWeek = addDays(athleteWeekStart(now), -7 * (PROGRESS_WEEK_COUNT - 1));
    const monthStart = `${athleteLocalDate(now).slice(0, 7)}-01`;

    const [weekly, activeWeeks, activeDays] = await Promise.all([
      this.aggregates.findWeeklyTotals(scope, { from: firstWeek }),
      this.aggregates.findActiveWeekStarts(scope),
      this.aggregates.findActiveDays(scope, { from: monthStart }),
    ]);
    return {
      sportTypeCode,
      weeks: zeroFilledWeeks(now, PROGRESS_WEEK_COUNT, weekly),
      streak: { weeks: streakWeeks(activeWeeks, now), activeDays },
    };
  }
}
