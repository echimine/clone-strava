import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ANALYTICS_EVENTS,
  ITINERARY_DELETED_EVENT,
  ITINERARY_SAVED_EVENT,
  type Itinerary,
  type ItineraryDeletedEvent,
  type ItinerarySavedEvent,
} from "@repo/contracts";
import { AnalyticsService } from "../../analytics/index.js";
import { itinerarySavedProperties, type ItinerarySportCategory } from "../domain/itinerary-analytics.js";

/**
 * Lifecycle events of an Itinerary (ADR-030 §9, §10), called by the use
 * cases only once a write has committed, never for a replayed `POST` that
 * wrote nothing: the domain event (`itineraries.itinerary.saved` /
 * `.deleted`, relayed on `user:{id}` by the realtime bridge) and the
 * PostHog lifecycle event.
 */
@Injectable()
export class ItineraryLifecycleEvents {
  constructor(
    private readonly events: EventEmitter2,
    private readonly analytics: AnalyticsService,
  ) {}

  created(userId: string, itinerary: Itinerary, sportCategory: ItinerarySportCategory): void {
    this.emitSaved(userId, itinerary);
    this.analytics.capture(ANALYTICS_EVENTS.ITINERARY_CREATED, userId, itinerarySavedProperties(itinerary, sportCategory));
  }

  updated(userId: string, itinerary: Itinerary, sportCategory: ItinerarySportCategory): void {
    this.emitSaved(userId, itinerary);
    this.analytics.capture(ANALYTICS_EVENTS.ITINERARY_UPDATED, userId, itinerarySavedProperties(itinerary, sportCategory));
  }

  renamed(userId: string, itinerary: Itinerary): void {
    this.emitSaved(userId, itinerary);
    this.analytics.capture(ANALYTICS_EVENTS.ITINERARY_RENAMED, userId, { itineraryId: itinerary.id });
  }

  deleted(userId: string, itineraryId: string): void {
    const event: ItineraryDeletedEvent = { itineraryId, userId };
    this.events.emit(ITINERARY_DELETED_EVENT, event);
    this.analytics.capture(ANALYTICS_EVENTS.ITINERARY_DELETED, userId, { itineraryId });
  }

  /**
   * Runs the computation of a save (create or full update) and captures
   * `itinerary_save_failed` when it fails with a `503` (an elevation
   * provider down), then rethrows.
   */
  async trackSaveFailure<T>(userId: string, compute: () => Promise<T>): Promise<T> {
    try {
      return await compute();
    } catch (error) {
      if (error instanceof ServiceUnavailableException) {
        const response = error.getResponse();
        const code = typeof response === "object" && "code" in response ? String(response.code) : "service_unavailable";
        this.analytics.capture(ANALYTICS_EVENTS.ITINERARY_SAVE_FAILED, userId, { errorCode: code });
      }
      throw error;
    }
  }

  private emitSaved(userId: string, itinerary: Itinerary): void {
    const event: ItinerarySavedEvent = { itineraryId: itinerary.id, userId, updatedAt: itinerary.updatedAt };
    this.events.emit(ITINERARY_SAVED_EVENT, event);
  }
}
