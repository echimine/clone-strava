import { Injectable } from "@nestjs/common";
import type { FollowRelation } from "../domain/follow-state.js";
import { FollowRepository } from "../repositories/follow.repository.js";

/**
 * The viewer's relation to each athlete, in one query (ADR-036 §1): every
 * id of `athleteIds` is in the map, `null` for the viewer themself.
 */
@Injectable()
export class FollowStatusesReader {
  constructor(private readonly follows: FollowRepository) {}

  async read(viewerId: string, athleteIds: string[]): Promise<Map<string, FollowRelation | null>> {
    const ids = [...new Set(athleteIds)];
    const rows = await this.follows.findStatuses(
      viewerId,
      ids.filter((id) => id !== viewerId),
    );
    const statusById = new Map(rows.map((row) => [row.athleteId, row.status]));
    return new Map(ids.map((id) => [id, id === viewerId ? null : (statusById.get(id) ?? "none")]));
  }
}
