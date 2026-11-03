import { Injectable } from "@nestjs/common";
import type { FollowListResponse, FollowRequestListResponse } from "@repo/contracts";
import type { FollowListPage } from "@repo/core/social";
import { AthleteIdentities } from "../identities/athlete-identities.js";

/**
 * Adds athlete identities to follow lists (ADR-036 §1), as for kudos
 * (ADR-034 §1): `social` returns athlete ids only.
 */
@Injectable()
export class FollowListAssembler {
  constructor(private readonly identities: AthleteIdentities) {}

  async assemble(page: FollowListPage): Promise<FollowListResponse> {
    const athlete = await this.identities.resolve(page.items.map((item) => item.athleteId));
    return {
      items: page.items.map((item) => ({
        athlete: athlete(item.athleteId),
        viewerFollowStatus: item.viewerFollowStatus,
      })),
      nextCursor: page.nextCursor,
    };
  }

  async assembleRequests(page: FollowListPage): Promise<FollowRequestListResponse> {
    const athlete = await this.identities.resolve(page.items.map((item) => item.athleteId));
    return {
      items: page.items.map((item) => ({
        athlete: athlete(item.athleteId),
        viewerFollowStatus: item.viewerFollowStatus,
        requestedAt: item.since.toISOString(),
      })),
      nextCursor: page.nextCursor,
    };
  }
}
