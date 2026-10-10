import { z } from "zod";

/**
 * Domain events emitted by the `itineraries` module after commit (ADR-030
 * §9, ADR-021 §3-4). The realtime bridge maps them onto the mobile protocol
 * (`itinerary.saved` / `itinerary.deleted`, topic `user:{id}`); domain
 * modules never publish to Redis themselves. Never emitted for a replayed
 * `POST` that wrote nothing.
 */
/** Creation, full update and rename. */
export const ITINERARY_SAVED_EVENT = "itineraries.itinerary.saved";
export const ITINERARY_DELETED_EVENT = "itineraries.itinerary.deleted";

/** Minimal payload (ADR-021 §3: "identifiers and what the listeners need"). */
export const itinerarySavedEventSchema = z.object({
  itineraryId: z.uuid(),
  userId: z.uuid(),
  /** The committed `updated_at`: the app ignores an echo of its own write. */
  updatedAt: z.iso.datetime(),
});
export type ItinerarySavedEvent = z.infer<typeof itinerarySavedEventSchema>;

export const itineraryDeletedEventSchema = z.object({
  itineraryId: z.uuid(),
  userId: z.uuid(),
});
export type ItineraryDeletedEvent = z.infer<typeof itineraryDeletedEventSchema>;
