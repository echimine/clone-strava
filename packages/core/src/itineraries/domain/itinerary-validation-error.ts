/**
 * An Itinerary invariant is violated (ADR-030 §4, §6). Pure domain error;
 * the module's services turn it into a `422 validation_error`.
 */
export class ItineraryValidationError extends Error {
  constructor(
    /** Path of the offending field in the request body, e.g. `legs.2.polyline6`. */
    readonly field: string,
    message: string,
  ) {
    super(message);
    this.name = "ItineraryValidationError";
  }
}
