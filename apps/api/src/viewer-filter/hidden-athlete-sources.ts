import { Injectable } from "@nestjs/common";
import { SocialService } from "@repo/core/social";

/**
 * One reason an athlete is hidden from a viewer (ADR-038 §7), read with one query in the module
 * that owns it. The viewer filter unions every source registered under `HIDDEN_ATHLETE_SOURCES`.
 */
export interface HiddenAthleteSource {
  hiddenFrom(viewerId: string): Promise<readonly string[]>;
}

/** The sources the viewer filter unions; see `ViewerFilterModule`. */
export const HIDDEN_ATHLETE_SOURCES = Symbol("HIDDEN_ATHLETE_SOURCES");

/** Blocks, in either direction (ADR-038 §8): owned by `social`. */
@Injectable()
export class BlockedAthletesSource implements HiddenAthleteSource {
  constructor(private readonly social: SocialService) {}

  hiddenFrom(viewerId: string): Promise<readonly string[]> {
    return this.social.getBlockedEitherWay(viewerId);
  }
}
