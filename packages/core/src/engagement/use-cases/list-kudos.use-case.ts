import { Injectable } from "@nestjs/common";
import { ActivitiesService, activityNotFound } from "../../activities/index.js";
import { decodeKudosCursor, encodeKudosCursor } from "../domain/kudos-cursor.js";
import type { KudosPage } from "../domain/kudos-view.js";
import { KudosRepository } from "../repositories/kudos.repository.js";
import { readKeysetPage } from "../services/keyset-page.js";

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
      throw activityNotFound();
    }
    const { rows, boundary: last } = await readKeysetPage(query, decodeKudosCursor, (after, take) =>
      this.kudos.findPage(activityId, after, take),
    );
    return {
      items: rows.map((row) => ({ athleteId: row.userId, givenAt: row.createdAt })),
      nextCursor: last ? encodeKudosCursor({ at: last.at, userId: last.userId }) : null,
    };
  }
}
