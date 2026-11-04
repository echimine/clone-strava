import { Injectable, Logger } from "@nestjs/common";
import { OnEvent } from "@nestjs/event-emitter";
import {
  ACCOUNT_DELETED_EVENT,
  ACTIVITY_DELETED_EVENT,
  COMMENT_DELETED_EVENT,
  type AccountDeletedEvent,
  type ActivityDeletedEvent,
  type CommentDeletedEvent,
} from "@repo/contracts";
import { CloseCasesOfGoneTargetUseCase } from "../use-cases/close-cases-of-gone-target.use-case.js";

/**
 * Closes the cases whose target disappeared (ADR-038 §10, §18: `moderation` reacts to deletions of
 * comments, Activities and users through domain events). A Media is never a Report's target (an
 * Activity is reported as a whole), so Media deletions are not listened to. Listeners never
 * throw (ADR-021 §3): a failure is logged, the case stays open for an Administrator to close.
 */
@Injectable()
export class TargetDeletionListener {
  private readonly logger = new Logger(TargetDeletionListener.name);

  constructor(private readonly closeCases: CloseCasesOfGoneTargetUseCase) {}

  @OnEvent(COMMENT_DELETED_EVENT, { async: true })
  async onCommentDeleted(event: CommentDeletedEvent): Promise<void> {
    await this.safely(`comment ${event.commentId}`, () =>
      this.closeCases.target("comment", event.commentId, event.bySanction),
    );
  }

  @OnEvent(ACTIVITY_DELETED_EVENT, { async: true })
  async onActivityDeleted(event: ActivityDeletedEvent): Promise<void> {
    await this.safely(`activity ${event.activityId}`, async () => [
      ...(await this.closeCases.target("activity", event.activityId, event.bySanction)),
      ...(await this.closeCases.commentsOfActivity(event.activityId)),
    ]);
  }

  @OnEvent(ACCOUNT_DELETED_EVENT, { async: true })
  async onAccountDeleted(event: AccountDeletedEvent): Promise<void> {
    await this.safely(`account ${event.userId}`, () => this.closeCases.author(event.userId, event.bySanction));
  }

  private async safely(target: string, close: () => Promise<string[]>): Promise<void> {
    try {
      const closed = await close();
      if (closed.length > 0) {
        this.logger.log({ closed }, `Report cases closed: ${target} is gone`);
      }
    } catch (error) {
      this.logger.error(`Report cases of ${target} not closed: ${String(error)}`);
    }
  }
}
