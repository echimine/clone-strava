import { Injectable } from "@nestjs/common";
import { readKeysetPage, type PageQuery, type ViewerExclusions } from "../../infrastructure/index.js";
import type { GalleryMediaPage } from "../domain/activity-media.js";
import { decodeGalleryCursor, encodeGalleryCursor } from "../domain/gallery-cursor.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { AggregateScopeResolver } from "../services/aggregate-scope-resolver.js";

/**
 * One keyset page of an athlete's Gallery (ADR-037 §9): the Media of their processed Activities
 * the viewer may see, with the rule of their Activities tab (ADR-036 §3). Newest Activity first,
 * then the Media order; `mediaFirst` plays no part. `422 invalid_cursor` on a foreign cursor.
 */
@Injectable()
export class GetAthleteGalleryPageUseCase {
  constructor(
    private readonly scopes: AggregateScopeResolver,
    private readonly media: ActivityMediaRepository,
  ) {}

  async execute(
    viewerId: string,
    athleteId: string,
    query: PageQuery,
    exclusions: ViewerExclusions,
  ): Promise<GalleryMediaPage> {
    const { visibilities } = await this.scopes.resolve(viewerId, athleteId);
    const { rows, boundary: last } = await readKeysetPage(query, decodeGalleryCursor, (after, take) =>
      this.media.findGalleryPage({
        userId: athleteId,
        visibilities,
        after,
        limit: take,
        excludedActivityIds: exclusions.reportedActivityIds,
      }),
    );
    return {
      items: rows.map((row) => ({
        id: row.id,
        activityId: row.activityId,
        kind: row.kind,
        width: row.width,
        height: row.height,
        durationMs: row.durationMs,
        folderKey: row.folderKey,
        activity: { id: row.activityId, title: row.activityTitle, startedAt: row.activityStartedAt },
      })),
      nextCursor: last
        ? encodeGalleryCursor({
            activityStartedAt: last.activityStartedAtMicros,
            activityId: last.activityId,
            position: last.position,
            createdAt: last.createdAtMicros,
            mediaId: last.id,
          })
        : null,
    };
  }
}
