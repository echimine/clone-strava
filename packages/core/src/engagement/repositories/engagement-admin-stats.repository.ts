import { Inject, Injectable } from "@nestjs/common";
import { and, count, isNull } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, notByUsers, withinRange, type InstantRange } from "../../infrastructure/index.js";

/** Kudos and comments given in a period (ADR-038 §15). */
export interface EngagementGrowthCounts {
  kudos: number;
  /** Comments written in the period and not deleted since. */
  comments: number;
}

/** Backoffice dashboard counts (ADR-038 §15) over `kudos` and `comment`, by their author. */
@Injectable()
export class EngagementAdminStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async countGrowth(range: InstantRange, excludedUserIds: readonly string[]): Promise<EngagementGrowthCounts> {
    const [kudos] = await this.db
      .select({ total: count() })
      .from(schema.kudos)
      .where(and(withinRange(schema.kudos.createdAt, range), notByUsers(schema.kudos.userId, excludedUserIds)));
    const [comments] = await this.db
      .select({ total: count() })
      .from(schema.comment)
      .where(
        and(
          withinRange(schema.comment.createdAt, range),
          isNull(schema.comment.deletedAt),
          notByUsers(schema.comment.userId, excludedUserIds),
        ),
      );
    return { kudos: kudos?.total ?? 0, comments: comments?.total ?? 0 };
  }
}
