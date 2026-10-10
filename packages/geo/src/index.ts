/**
 * Pure geographic functions shared by Activities and Itineraries
 * (ADR-030 §4): no Nest, no database, no I/O. Tuning parameters (step,
 * hysteresis, tolerance) are always passed by the caller.
 */
export * from "./types.js";
export { haversineDistanceM, trackDistanceM } from "./distance.js";
export { elevationGainM } from "./elevation-gain.js";
export { decodePolyline, encodePolyline, InvalidPolylineError } from "./polyline.js";
export { resampleAlongTrack } from "./resample.js";
export { simplifyTrack } from "./simplify.js";
