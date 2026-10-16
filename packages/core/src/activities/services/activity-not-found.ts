import { NotFoundException } from "@nestjs/common";

/** `404 activity_not_found` (ADR-033 §2): unknown, or not visible to the viewer, never `403`. */
export function activityNotFound(): NotFoundException {
  return new NotFoundException({ code: "activity_not_found", message: "Activity not found" });
}
