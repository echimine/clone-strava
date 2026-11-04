import { Injectable } from "@nestjs/common";
import type { PageQuery, ViewerExclusions } from "../../infrastructure/index.js";
import type { FollowListKind, FollowListPage } from "../domain/follow-list.js";
import { FollowPageReader } from "../services/follow-page-reader.js";

/**
 * Follow lists (ADR-036 §1): an athlete's accepted `followers` or whom they
 * are `following`. Most recent first by keyset pages; each entry carries the
 * viewer's relation to the listed athlete. Any signed-in athlete may read
 * any athlete's lists; athletes hidden from the viewer are left out (ADR-038 §7).
 */
@Injectable()
export class ListFollowsUseCase {
  constructor(private readonly pages: FollowPageReader) {}

  execute(
    viewerId: string,
    athleteId: string,
    kind: FollowListKind,
    query: PageQuery,
    exclusions: ViewerExclusions,
  ): Promise<FollowListPage> {
    return this.pages.read(viewerId, athleteId, kind, "accepted", query, exclusions);
  }
}
