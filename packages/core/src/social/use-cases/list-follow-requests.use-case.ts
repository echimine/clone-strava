import { Injectable } from "@nestjs/common";
import type { PageQuery } from "../../infrastructure/index.js";
import type { FollowListPage } from "../domain/follow-list.js";
import { FollowPageReader } from "../services/follow-page-reader.js";

/**
 * The signed-in athlete's incoming follow requests (ADR-036 §1): `pending`
 * follows of them, most recent first by keyset pages; `since` is when each
 * request was made.
 */
@Injectable()
export class ListFollowRequestsUseCase {
  constructor(private readonly pages: FollowPageReader) {}

  execute(userId: string, query: PageQuery): Promise<FollowListPage> {
    return this.pages.read(userId, userId, "followers", "pending", query);
  }
}
