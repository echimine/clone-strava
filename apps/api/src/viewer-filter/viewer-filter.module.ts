import { Module } from "@nestjs/common";
import { BansModule } from "@repo/core/auth";
import { ModerationModule } from "@repo/core/moderation";
import { SocialModule } from "@repo/core/social";
import {
  BannedAthletesSource,
  BlockedAthletesSource,
  HIDDEN_ATHLETE_SOURCES,
  type HiddenAthleteSource,
} from "./hidden-athlete-sources.js";
import { ViewerFilter } from "./viewer-filter.js";

/**
 * The viewer filter (ADR-038 §7), imported by every feature module with a read path.
 *
 * A reason to hide an athlete is one `HiddenAthleteSource` class: Blocks (`social`) and active
 * Bans (`auth`, ADR-038 §6). A new one goes into `providers` and the `inject` list below. No read
 * path changes, since they all take the resulting `hiddenAthleteIds`.
 */
@Module({
  imports: [SocialModule, ModerationModule, BansModule],
  providers: [
    BlockedAthletesSource,
    BannedAthletesSource,
    {
      provide: HIDDEN_ATHLETE_SOURCES,
      useFactory: (...sources: HiddenAthleteSource[]) => sources,
      inject: [BlockedAthletesSource, BannedAthletesSource],
    },
    ViewerFilter,
  ],
  exports: [ViewerFilter],
})
export class ViewerFilterModule {}
