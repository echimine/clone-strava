import { Injectable } from "@nestjs/common";
import { AuthorActivityResolver } from "../services/author-activity-resolver.js";
import { MediaRemover } from "../services/media-remover.js";

/**
 * `DELETE /v1/activities/:id/media/:mediaId` (ADR-037 §4): the author deletes a Media of their
 * Activity ({@link MediaRemover}), also when the row is already gone (files of a Media never
 * confirmed).
 */
@Injectable()
export class DeleteMediaUseCase {
  constructor(
    private readonly authorActivity: AuthorActivityResolver,
    private readonly remover: MediaRemover,
  ) {}

  async execute(userId: string, activityId: string, mediaId: string): Promise<void> {
    const activity = await this.authorActivity.resolve(userId, activityId);
    await this.remover.remove(activity, mediaId, { bySanction: false });
  }
}
