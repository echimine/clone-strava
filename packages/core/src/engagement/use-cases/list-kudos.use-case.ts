import { Injectable, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import { ActivitiesService } from "../../activities/index.js";
import {
  decodeKudosCursor,
  encodeKudosCursor,
  InvalidKudosCursorError,
  type KudosCursor,
} from "../domain/kudos-cursor.js";
import type { KudosPage } from "../domain/kudos-view.js";
import { KudosRepository } from "../repositories/kudos.repository.js";

/**
 * `GET /v1/activities/:id/kudos` (ADR-034 §1): who gave kudos to an
 * Activity the viewer can see (`404 activity_not_found` otherwise, through
 * `ActivitiesService`: ADR-021 §2), most recent first, by keyset pages.
 */
@Injectable()
export class ListKudosUseCase {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly kudos: KudosRepository,
  ) {}

  async execute(viewerId: string, activityId: string, query: { cursor?: string; limit: number }): Promise<KudosPage> {
    if (!(await this.activities.getVisible(viewerId, activityId))) {
      throw new NotFoundException({ code: "activity_not_found", message: "Activity not found" });
    }
    const after = query.cursor === undefined ? undefined : this.decode(query.cursor);
    const rows = await this.kudos.findPage(activityId, after, query.limit + 1);
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      items: page.map((row) => ({ athleteId: row.userId, givenAt: row.createdAt })),
      nextCursor: rows.length > query.limit && last ? encodeKudosCursor({ at: last.at, userId: last.userId }) : null,
    };
  }

  private decode(cursor: string): KudosCursor {
    try {
      return decodeKudosCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidKudosCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid kudos cursor" });
      }
      throw error;
    }
  }
}
