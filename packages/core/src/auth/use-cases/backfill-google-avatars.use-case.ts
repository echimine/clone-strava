import { Injectable } from "@nestjs/common";
import { AuthUserRepository } from "../repositories/auth-user.repository.js";
import { GoogleAvatarCopyEnqueuer } from "../services/google-avatar-copy-enqueuer.js";

const PAGE_SIZE = 500;

/**
 * The one-off Google photo backfill (ADR-037 §2): a `copy-google-avatar` job for every existing
 * Google account with a `user.image`. Replayable: a copy already waiting is not enqueued twice,
 * and the job copies nothing for an athlete who already has an Avatar.
 */
@Injectable()
export class BackfillGoogleAvatarsUseCase {
  constructor(
    private readonly users: AuthUserRepository,
    private readonly enqueuer: GoogleAvatarCopyEnqueuer,
  ) {}

  /** Returns the number of jobs enqueued. */
  async execute(): Promise<number> {
    let count = 0;
    let afterId: string | null = null;
    for (;;) {
      const page = await this.users.findGoogleAccountImages(afterId, PAGE_SIZE);
      for (const { id, image } of page) {
        if (image && (await this.enqueuer.enqueue(id, image))) {
          count++;
        }
      }
      if (page.length < PAGE_SIZE) {
        return count;
      }
      afterId = page[page.length - 1]!.id;
    }
  }
}
