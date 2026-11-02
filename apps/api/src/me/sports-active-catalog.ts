import { Injectable } from "@nestjs/common";
import { SportsService } from "@repo/core/sports";
import type { ActiveSportCatalog } from "@repo/core/users";

/**
 * Adapter of the `users` port {@link ActiveSportCatalog}, backed by
 * `sports`: `users` depends on no module (ADR-021 §2), so the app composing
 * the modules wires the two together (§8).
 */
@Injectable()
export class SportsActiveCatalog implements ActiveSportCatalog {
  constructor(private readonly sports: SportsService) {}

  async activeCodes(): Promise<ReadonlySet<string>> {
    return new Set((await this.sports.list()).map((sport) => sport.code));
  }
}
