import { Injectable } from "@nestjs/common";
import { SocialService } from "../../social/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { FeedPageBuilder } from "../services/feed-page-builder.js";
import type { FeedActivityPage } from "../domain/feed-activity.js";

/**
 * Feed steps 1-2 of ADR-021 §6 (ADR-029): followees, then one keyset page of
 * activities with their stats and map fields, each read from this module's
 * own tables. Authors and engagement counts are composed by the caller.
 */
@Injectable()
export class GetFeedPageUseCase {
  constructor(
    private readonly social: SocialService,
    private readonly activities: ActivityRepository,
    private readonly pages: FeedPageBuilder,
  ) {}

  async execute(viewerId: string, query: { cursor?: string; limit: number }): Promise<FeedActivityPage> {
    const before = this.pages.decodeCursor(query.cursor);
    const followeeIds = await this.social.getFolloweeIds(viewerId);
    const rows = await this.activities.findFeedPage({ viewerId, followeeIds, before, limit: query.limit });
    return this.pages.build(rows, query.limit);
  }
}
