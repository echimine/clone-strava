import { Injectable } from "@nestjs/common";
import type { ListKudosResponse } from "@repo/contracts";
import type { KudosPage } from "@repo/core/engagement";
import { AthleteIdentities } from "../identities/athlete-identities.js";

/**
 * Adds athlete identities to a page of kudos (ADR-034 §1), as the feed does
 * (ADR-029 §2): `engagement` returns athlete ids only.
 */
@Injectable()
export class KudosAssembler {
  constructor(private readonly identities: AthleteIdentities) {}

  async assemble(page: KudosPage): Promise<ListKudosResponse> {
    const athlete = await this.identities.resolve(page.items.map((item) => item.athleteId));
    return {
      items: page.items.map((item) => ({ athlete: athlete(item.athleteId), givenAt: item.givenAt.toISOString() })),
      nextCursor: page.nextCursor,
    };
  }
}
