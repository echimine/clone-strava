import { Injectable } from "@nestjs/common";
import type { PageQuery, ViewerExclusions } from "../../infrastructure/index.js";
import type { FollowListPage } from "../domain/follow-list.js";
import { FollowPageReader } from "../services/follow-page-reader.js";

/**
 * The signed-in athlete's incoming follow requests (ADR-036 §1): `pending`
 * follows of them, most recent first by keyset pages; `since` is when each
 * request was made. Requests of athletes hidden from them (a Ban, ADR-038 §6)
 * are left out.
 */
@Injectable()
export class ListFollowRequestsUseCase {
  constructor(private readonly pages: FollowPageReader) {}

  execute(userId: string, query: PageQuery, exclusions: ViewerExclusions): Promise<FollowListPage> {
    return this.pages.read(userId, userId, "followers", "pending", query, exclusions);
  }
}
