import { Module } from "@nestjs/common";
import { ModerationModule } from "@repo/core/moderation";
import { SocialModule } from "@repo/core/social";
import { BlockedAthletesSource, HIDDEN_ATHLETE_SOURCES, type HiddenAthleteSource } from "./hidden-athlete-sources.js";
import { ViewerFilter } from "./viewer-filter.js";

/**
 * The viewer filter (ADR-038 §7), imported by every feature module with a read path.
 *
 * A new reason to hide an athlete (e.g. active Bans, owned by `auth`) is one more
 * `HiddenAthleteSource` class: add it to `providers` and to the `inject` list below. No read path
 * changes, since they all take the resulting `hiddenAthleteIds`.
 */
@Module({
  imports: [SocialModule, ModerationModule],
  providers: [
    BlockedAthletesSource,
    {
      provide: HIDDEN_ATHLETE_SOURCES,
      useFactory: (...sources: HiddenAthleteSource[]) => sources,
      inject: [BlockedAthletesSource],
    },
    ViewerFilter,
  ],
  exports: [ViewerFilter],
})
export class ViewerFilterModule {}
