import { Injectable } from "@nestjs/common";
import type { AthleteStatsResponse } from "@repo/contracts";
import { ActivityAggregateRepository } from "../repositories/activity-aggregate.repository.js";
import { AggregateScopeResolver } from "../services/aggregate-scope-resolver.js";
import { addDays, athleteLocalDate, athleteWeekStart } from "../domain/athlete-weeks.js";

/** ACTIVITÉ averages the full weeks before the current one, so it stays stable during the week. */
const RECENT_WEEK_COUNT = 4;

/**
 * An athlete's Statistiques as a viewer sees them (ADR-036 §4), over the Activities that viewer
 * may see: recent weekly averages, year to date (from 1 January in `Europe/Paris`) and all time.
 * `sportTypeCode` omitted: all sports.
 */
@Injectable()
export class GetAthleteStatsUseCase {
  constructor(
    private readonly scopes: AggregateScopeResolver,
    private readonly aggregates: ActivityAggregateRepository,
  ) {}

  async execute(
    viewerId: string,
    athleteId: string,
    sportTypeCode?: string,
    now = new Date(),
  ): Promise<AthleteStatsResponse> {
    const scope = await this.scopes.resolve(viewerId, athleteId, sportTypeCode);
    const currentWeek = athleteWeekStart(now);
    const yearStart = `${athleteLocalDate(now).slice(0, 4)}-01-01`;

    const [recent, yearToDate, allTime] = await Promise.all([
      this.aggregates.findTotals(scope, { from: addDays(currentWeek, -7 * RECENT_WEEK_COUNT), to: currentWeek }),
      this.aggregates.findTotals(scope, { from: yearStart }),
      this.aggregates.findTotals(scope, {}),
    ]);
    return {
      sportTypeCode,
      recent: {
        weeks: RECENT_WEEK_COUNT,
        activitiesPerWeek: recent.activityCount / RECENT_WEEK_COUNT,
        movingTimeSPerWeek: recent.movingTimeS / RECENT_WEEK_COUNT,
        distanceMPerWeek: recent.distanceM / RECENT_WEEK_COUNT,
      },
      yearToDate,
      allTime: {
        activityCount: allTime.activityCount,
        distanceM: allTime.distanceM,
        elevationGainM: allTime.elevationGainM,
      },
    };
  }
}
