import { Injectable } from "@nestjs/common";
import { readKeysetPage, type PageQuery, type ViewerExclusions } from "../../infrastructure/index.js";
import { decodeFollowCursor, encodeFollowCursor } from "../domain/follow-cursor.js";
import type { FollowListKind, FollowListPage } from "../domain/follow-list.js";
import type { FollowStatus } from "../domain/follow-state.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { FollowStatusesReader } from "./follow-statuses-reader.js";

/**
 * One keyset page of `follow` rows of one side of an athlete (ADR-036 §1), most recent first,
 * each listed athlete with the viewer's relation to them. Shared by the follow lists and the
 * follow requests.
 */
@Injectable()
export class FollowPageReader {
  constructor(
    private readonly follows: FollowRepository,
    private readonly statuses: FollowStatusesReader,
  ) {}

  async read(
    viewerId: string,
    athleteId: string,
    side: FollowListKind,
    status: FollowStatus,
    query: PageQuery,
    exclusions: ViewerExclusions,
  ): Promise<FollowListPage> {
    const { rows, boundary: last } = await readKeysetPage(query, decodeFollowCursor, (after, take) =>
      this.follows.findPage(athleteId, side, status, after, take, exclusions.hiddenAthleteIds),
    );
    const relation = await this.statuses.read(
      viewerId,
      rows.map((row) => row.athleteId),
    );
    return {
      items: rows.map((row) => ({
        athleteId: row.athleteId,
        viewerFollowStatus: relation.get(row.athleteId) ?? null,
        since: row.createdAt,
      })),
      nextCursor: last ? encodeFollowCursor({ at: last.at, athleteId: last.athleteId }) : null,
    };
  }
}
