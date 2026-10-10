/**
 * Pure geographic functions shared by Activities and Itineraries
 * (ADR-030 §4): no Nest, no database, no I/O. Tuning parameters (step,
 * hysteresis, tolerance) are always passed by the caller.
 */
export * from "./types.js";
export { haversineDistanceM } from "./distance.js";
export { encodePolyline } from "./polyline.js";
export { simplifyTrack } from "./simplify.js";
