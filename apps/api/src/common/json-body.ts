/**
 * Max JSON request body. Express's 100 kB default is too small for an
 * Itinerary body: up to 50,000 polyline6 points across its Legs
 * (ADR-030 §6).
 */
export const JSON_BODY_LIMIT = "1mb";
