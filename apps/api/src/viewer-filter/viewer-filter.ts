import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { isAthleteHidden, type ViewerExclusions } from "@repo/core/infrastructure";
import { ModerationService } from "@repo/core/moderation";
import { HIDDEN_ATHLETE_SOURCES, type HiddenAthleteSource } from "./hidden-athlete-sources.js";

/**
 * The viewer filter (ADR-038 §7): what one viewer must not see, built per request with one query
 * per owning module, run in parallel. Hidden athletes come from every `HiddenAthleteSource`
 * (Blocks and active Bans), reported items from `moderation`.
 * Controllers pass the result to every read method of `activities`, `engagement`, `social` and
 * `users` as an exclusion parameter.
 */
@Injectable()
export class ViewerFilter {
  constructor(
    @Inject(HIDDEN_ATHLETE_SOURCES) private readonly sources: readonly HiddenAthleteSource[],
    private readonly moderation: ModerationService,
  ) {}

  async for(viewerId: string): Promise<ViewerExclusions> {
    const [hidden, reported] = await Promise.all([
      Promise.all(this.sources.map((source) => source.hiddenFrom(viewerId))),
      this.moderation.getReportedItems(viewerId),
    ]);
    return {
      hiddenAthleteIds: [...new Set(hidden.flat())].filter((id) => id !== viewerId),
      reportedActivityIds: reported.activityIds,
      reportedCommentIds: reported.commentIds,
    };
  }
}

/**
 * `404 athlete_not_found` for an athlete hidden from the viewer (ADR-038 §6, §8: "Ce profil n'est
 * plus disponible"), the same answer as for an unknown one.
 */
export function assertAthleteVisible(exclusions: ViewerExclusions, athleteId: string): void {
  if (isAthleteHidden(exclusions, athleteId)) {
    throw new NotFoundException({ code: "athlete_not_found", message: "Athlete not found" });
  }
}
