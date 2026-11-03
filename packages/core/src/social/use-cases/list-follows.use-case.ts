import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { decodeFollowCursor, encodeFollowCursor, InvalidFollowCursorError, type FollowCursor } from "../domain/follow-cursor.js";
import type { FollowListKind, FollowListPage } from "../domain/follow-list.js";
import { FollowRepository } from "../repositories/follow.repository.js";
import { FollowStatusesReader } from "../services/follow-statuses-reader.js";

/**
 * Follow lists (ADR-036 §1): an athlete's accepted `followers` or whom they
 * are `following`, and the viewer's own incoming `requests` (pending). Most
 * recent first by keyset pages; each entry carries the viewer's relation to
 * the listed athlete. Any signed-in athlete may read any athlete's lists.
 */
@Injectable()
export class ListFollowsUseCase {
  constructor(
    private readonly follows: FollowRepository,
    private readonly statuses: FollowStatusesReader,
  ) {}

  execute(
    viewerId: string,
    athleteId: string,
    kind: FollowListKind | "requests",
    query: { cursor?: string; limit: number },
  ): Promise<FollowListPage> {
    return kind === "requests"
      ? this.page(viewerId, viewerId, "followers", "pending", query)
      : this.page(viewerId, athleteId, kind, "accepted", query);
  }

  private async page(
    viewerId: string,
    athleteId: string,
    side: FollowListKind,
    status: "pending" | "accepted",
    query: { cursor?: string; limit: number },
  ): Promise<FollowListPage> {
    const after = query.cursor === undefined ? undefined : decodeOr422(query.cursor);
    const fetched = await this.follows.findPage(athleteId, side, status, after, query.limit + 1);
    const rows = fetched.slice(0, query.limit);
    const last = fetched.length > query.limit ? rows.at(-1) : undefined;
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

function decodeOr422(value: string): FollowCursor {
  try {
    return decodeFollowCursor(value);
  } catch (error) {
    if (error instanceof InvalidFollowCursorError) {
      throw new UnprocessableEntityException({ code: "invalid_cursor", message: error.message });
    }
    throw error;
  }
}
