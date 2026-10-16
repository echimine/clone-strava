import { Inject, Injectable, Logger } from "@nestjs/common";
import { OnEvent } from "@nestjs/event-emitter";
import {
  ACTIVITY_DELETED,
  ACTIVITY_FAILED,
  ACTIVITY_IMPORT_COMPLETED,
  ACTIVITY_IMPORT_FAILED,
  ACTIVITY_PROCESSED,
  ACTIVITY_SEGMENTS_MATCHED,
  ACTIVITY_UPDATED,
  COMMENT_CREATED,
  COMMENT_DELETED,
  COMMENT_UPDATED,
  ITINERARY_DELETED,
  ITINERARY_SAVED,
  KUDOS_CHANGED,
  activityTopic,
  userTopic,
  type RealtimePublisher,
} from "@repo/realtime";
import {
  ACTIVITY_DELETED_EVENT,
  ACTIVITY_FAILED_EVENT,
  ACTIVITY_IMPORT_COMPLETED_EVENT,
  ACTIVITY_IMPORT_FAILED_EVENT,
  ACTIVITY_PROCESSED_EVENT,
  ACTIVITY_UPDATED_EVENT,
  COMMENT_ADDED_EVENT,
  COMMENT_DELETED_EVENT,
  COMMENT_EDITED_EVENT,
  ITINERARY_DELETED_EVENT,
  ITINERARY_SAVED_EVENT,
  KUDOS_GIVEN_EVENT,
  KUDOS_REMOVED_EVENT,
  SEGMENTS_EFFORTS_MATCHED_EVENT,
  type ActivityDeletedEvent,
  type ActivityFailedEvent,
  type ActivityImportCompletedEvent,
  type ActivityImportFailedEvent,
  type ActivityProcessedEvent,
  type ActivityUpdatedEvent,
  type CommentEvent,
  type ItineraryDeletedEvent,
  type ItinerarySavedEvent,
  type KudosEvent,
  type SegmentsEffortsMatchedEvent,
} from "@repo/contracts";
import { REALTIME_PUBLISHER } from "../realtime.constants.js";

/**
 * The only listener that forwards domain events to the mobile app
 * (ADR-021 §4, amends ADR-010). Domain modules never publish to Redis
 * themselves; they emit domain events, and this bridge holds the explicit
 * forwarding table (allow-list) from internal event name to mobile event
 * type, topics and minimal payload:
 *
 * | Domain event                     | Mobile event                | Topics                         |
 * |----------------------------------|-----------------------------|--------------------------------|
 * | `activities.activity.processed`  | `activity.processed`        | `user:{userId}`                |
 * | `activities.activity.failed`     | `activity.failed`           | `user:{userId}`                |
 * | `activities.activity.updated`    | `activity.updated`          | `user:{userId}`, `activity:{id}` |
 * | `activities.activity.deleted`    | `activity.deleted`          | `user:{userId}`, `activity:{id}` |
 * | `segments.efforts.matched`       | `activity.segments_matched` | `user:{userId}`                |
 * | `activities.import.completed`    | `activity_import.completed` | `user:{userId}`                |
 * | `activities.import.failed`       | `activity_import.failed`    | `user:{userId}`                |
 * | `itineraries.itinerary.saved`    | `itinerary.saved`           | `user:{userId}`                |
 * | `itineraries.itinerary.deleted`  | `itinerary.deleted`         | `user:{userId}`                |
 * | `engagement.comment.added`       | `comment.created`           | `activity:{id}`                |
 * | `engagement.comment.edited`      | `comment.updated`           | `activity:{id}`                |
 * | `engagement.comment.deleted`     | `comment.deleted`           | `activity:{id}`                |
 * | `engagement.kudos.given/removed` | `kudos.changed`             | `activity:{id}`                |
 *
 * `activity:{id}` reaches everyone with the Activity's detail open
 * (subscription grant, ADR-034 §5).
 *
 * An event absent from this table never reaches a client (ADR-021 §4).
 *
 * Listener rules (ADR-021 §3): async, never throw (each handler catches
 * and logs a `warn`), fire-and-forget (a Redis failure is logged and
 * ignored, ADR-021 §4 "Fire-and-forget").
 */
@Injectable()
export class RealtimeBridge {
  private readonly logger = new Logger(RealtimeBridge.name);

  constructor(@Inject(REALTIME_PUBLISHER) private readonly publisher: RealtimePublisher) {}

  @OnEvent(ACTIVITY_PROCESSED_EVENT, { async: true })
  async onActivityProcessed(event: ActivityProcessedEvent): Promise<void> {
    await this.forward(ACTIVITY_PROCESSED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ACTIVITY_PROCESSED, {
        activityId: event.activityId,
        status: "processed",
        at: new Date().toISOString(),
      }),
    );
  }

  @OnEvent(ACTIVITY_FAILED_EVENT, { async: true })
  async onActivityFailed(event: ActivityFailedEvent): Promise<void> {
    await this.forward(ACTIVITY_FAILED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ACTIVITY_FAILED, {
        activityId: event.activityId,
        status: "failed",
        at: new Date().toISOString(),
      }),
    );
  }

  /**
   * ADR-033 §8: the author's other devices reload the card and the open detail;
   * ADR-034 §5: so does every other viewer with the detail open.
   */
  @OnEvent(ACTIVITY_UPDATED_EVENT, { async: true })
  async onActivityUpdated(event: ActivityUpdatedEvent): Promise<void> {
    await this.forward(ACTIVITY_UPDATED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent(
        [userTopic(event.userId), activityTopic(event.activityId)],
        ACTIVITY_UPDATED,
        { activityId: event.activityId, changedFields: event.changedFields },
      ),
    );
  }

  /**
   * ADR-033 §8: the author's other devices drop the card and the open detail;
   * ADR-034 §5: every other viewer's open detail becomes unavailable.
   */
  @OnEvent(ACTIVITY_DELETED_EVENT, { async: true })
  async onActivityDeleted(event: ActivityDeletedEvent): Promise<void> {
    await this.forward(ACTIVITY_DELETED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent(
        [userTopic(event.userId), activityTopic(event.activityId)],
        ACTIVITY_DELETED,
        { activityId: event.activityId },
      ),
    );
  }

  /** ADR-034 §5: viewers with the detail open fetch the new comment. */
  @OnEvent(COMMENT_ADDED_EVENT, { async: true })
  async onCommentAdded(event: CommentEvent): Promise<void> {
    await this.forwardComment(COMMENT_ADDED_EVENT, COMMENT_CREATED, event);
  }

  /** ADR-034 §5: viewers with the detail open fetch the edited comment. */
  @OnEvent(COMMENT_EDITED_EVENT, { async: true })
  async onCommentEdited(event: CommentEvent): Promise<void> {
    await this.forwardComment(COMMENT_EDITED_EVENT, COMMENT_UPDATED, event);
  }

  /** ADR-034 §5: viewers with the detail open remove the comment. */
  @OnEvent(COMMENT_DELETED_EVENT, { async: true })
  async onCommentDeleted(event: CommentEvent): Promise<void> {
    await this.forwardComment(COMMENT_DELETED_EVENT, COMMENT_DELETED, event);
  }

  /** ADR-034 §5: viewers with the detail open reload its engagement. */
  @OnEvent(KUDOS_GIVEN_EVENT, { async: true })
  async onKudosGiven(event: KudosEvent): Promise<void> {
    await this.forwardKudos(KUDOS_GIVEN_EVENT, event);
  }

  /** ADR-034 §5. */
  @OnEvent(KUDOS_REMOVED_EVENT, { async: true })
  async onKudosRemoved(event: KudosEvent): Promise<void> {
    await this.forwardKudos(KUDOS_REMOVED_EVENT, event);
  }

  @OnEvent(SEGMENTS_EFFORTS_MATCHED_EVENT, { async: true })
  async onSegmentsEffortsMatched(event: SegmentsEffortsMatchedEvent): Promise<void> {
    await this.forward(SEGMENTS_EFFORTS_MATCHED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent(
        [userTopic(event.userId)],
        ACTIVITY_SEGMENTS_MATCHED,
        {
          activityId: event.activityId,
          status: "segments_matched",
          at: new Date().toISOString(),
        },
      ),
    );
  }

  /** ADR-028 §10. */
  @OnEvent(ACTIVITY_IMPORT_COMPLETED_EVENT, { async: true })
  async onActivityImportCompleted(event: ActivityImportCompletedEvent): Promise<void> {
    await this.forward(ACTIVITY_IMPORT_COMPLETED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ACTIVITY_IMPORT_COMPLETED, {
        importId: event.importId,
        activityId: event.activityId,
        status: event.outcome,
        at: new Date().toISOString(),
      }),
    );
  }

  /** ADR-028 §10. */
  @OnEvent(ACTIVITY_IMPORT_FAILED_EVENT, { async: true })
  async onActivityImportFailed(event: ActivityImportFailedEvent): Promise<void> {
    await this.forward(ACTIVITY_IMPORT_FAILED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ACTIVITY_IMPORT_FAILED, {
        importId: event.importId,
        status: "failed",
        code: event.code,
        at: new Date().toISOString(),
      }),
    );
  }

  /** ADR-030 §9: creation, full update and rename. No catch-up (ADR-010). */
  @OnEvent(ITINERARY_SAVED_EVENT, { async: true })
  async onItinerarySaved(event: ItinerarySavedEvent): Promise<void> {
    await this.forward(ITINERARY_SAVED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ITINERARY_SAVED, {
        itineraryId: event.itineraryId,
        updatedAt: event.updatedAt,
      }),
    );
  }

  /** ADR-030 §9. */
  @OnEvent(ITINERARY_DELETED_EVENT, { async: true })
  async onItineraryDeleted(event: ItineraryDeletedEvent): Promise<void> {
    await this.forward(ITINERARY_DELETED_EVENT, event.userId, () =>
      this.publisher.publishRealtimeEvent([userTopic(event.userId)], ITINERARY_DELETED, {
        itineraryId: event.itineraryId,
      }),
    );
  }

  private async forwardComment(
    eventName: string,
    type: typeof COMMENT_CREATED | typeof COMMENT_UPDATED | typeof COMMENT_DELETED,
    event: CommentEvent,
  ): Promise<void> {
    await this.forward(eventName, event.userId, () =>
      this.publisher.publishRealtimeEvent([activityTopic(event.activityId)], type, {
        activityId: event.activityId,
        commentId: event.commentId,
      }),
    );
  }

  private async forwardKudos(eventName: string, event: KudosEvent): Promise<void> {
    await this.forward(eventName, event.userId, () =>
      this.publisher.publishRealtimeEvent([activityTopic(event.activityId)], KUDOS_CHANGED, {
        activityId: event.activityId,
      }),
    );
  }

  private async forward(
    eventName: string,
    userId: string,
    publish: () => Promise<void>,
  ): Promise<void> {
    try {
      await publish();
    } catch (error) {
      // Listeners never throw (ADR-021 §3): a publish failure never fails
      // the emitter, and the mobile app resyncs on reconnection (ADR-010).
      this.logger.warn(`Failed to forward ${eventName} for user ${userId}: ${String(error)}`);
    }
  }
}
