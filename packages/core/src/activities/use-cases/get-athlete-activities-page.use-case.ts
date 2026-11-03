import { Injectable } from "@nestjs/common";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AggregateScopeResolver } from "../services/aggregate-scope-resolver.js";
import { FeedPageBuilder } from "../services/feed-page-builder.js";
import type { FeedActivityPage } from "../domain/feed-activity.js";

/**
 * One keyset page of an athlete's processed Activities that the viewer may see (ADR-036 §3, the
 * rule of `getVisible`): the owner all of theirs, an accepted follower `public` and `followers`,
 * anyone else `public`. Same page as the feed; the caller adds authors and engagement.
 */
@Injectable()
export class GetAthleteActivitiesPageUseCase {
  constructor(
    private readonly scopes: AggregateScopeResolver,
    private readonly activities: ActivityRepository,
    private readonly pages: FeedPageBuilder,
  ) {}

  async execute(
    viewerId: string,
    athleteId: string,
    query: { cursor?: string; limit: number },
  ): Promise<FeedActivityPage> {
    const before = this.pages.decodeCursor(query.cursor);
    const { visibilities } = await this.scopes.resolve(viewerId, athleteId);
    const rows = await this.activities.findAthletePage({ userId: athleteId, visibilities, before, limit: query.limit });
    return this.pages.build(rows, query.limit);
  }
}
