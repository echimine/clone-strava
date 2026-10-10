import { Inject, Injectable, Logger } from "@nestjs/common";
import { OnEvent } from "@nestjs/event-emitter";
import {
  ACTIVITY_FAILED,
  ACTIVITY_IMPORT_COMPLETED,
  ACTIVITY_IMPORT_FAILED,
  ACTIVITY_PROCESSED,
  ACTIVITY_SEGMENTS_MATCHED,
  ITINERARY_DELETED,
  ITINERARY_SAVED,
  userTopic,
  type RealtimePublisher,
} from "@repo/realtime";
import {
  ACTIVITY_FAILED_EVENT,
  ACTIVITY_IMPORT_COMPLETED_EVENT,
  ACTIVITY_IMPORT_FAILED_EVENT,
  ACTIVITY_PROCESSED_EVENT,
  ITINERARY_DELETED_EVENT,
  ITINERARY_SAVED_EVENT,
  SEGMENTS_EFFORTS_MATCHED_EVENT,
  type ActivityFailedEvent,
  type ActivityImportCompletedEvent,
  type ActivityImportFailedEvent,
  type ActivityProcessedEvent,
  type ItineraryDeletedEvent,
  type ItinerarySavedEvent,
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
 * | Domain event                    | Mobile event                 |
 * |----------------------------------|-------------------------------|
 * | `activities.activity.processed`  | `activity.processed`          |
 * | `activities.activity.failed`     | `activity.failed`             |
 * | `segments.efforts.matched`       | `activity.segments_matched`   |
 * | `activities.import.completed`    | `activity_import.completed`   |
 * | `activities.import.failed`       | `activity_import.failed`      |
 * | `itineraries.itinerary.saved`    | `itinerary.saved`             |
 * | `itineraries.itinerary.deleted`  | `itinerary.deleted`           |
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
