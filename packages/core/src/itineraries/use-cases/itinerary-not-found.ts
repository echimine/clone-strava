import { NotFoundException } from "@nestjs/common";

/** Unknown or someone else's Itinerary: `404`, never `403` (ADR-030 §6). */
export function itineraryNotFound(): NotFoundException {
  return new NotFoundException({ code: "not_found", message: "Itinerary not found" });
}
