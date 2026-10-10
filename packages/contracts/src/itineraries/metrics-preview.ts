import { z } from "zod";
import { itineraryElevationSourceSchema, itineraryGeometrySchema } from "./geometry.js";

/** `POST /v1/itineraries/metrics-preview` body (ADR-030 §6): the save body without name or sport. */
export const itineraryMetricsPreviewRequestSchema = itineraryGeometrySchema;
export type ItineraryMetricsPreviewRequest = z.infer<typeof itineraryMetricsPreviewRequestSchema>;

/**
 * Distance and elevation gain of an Itinerary, computed by the server
 * (ADR-030 §3). The preview returns exactly what a save would store.
 */
export const itineraryMetricsSchema = z.object({
  distanceM: z.number().nonnegative(),
  elevationGainM: z.number().nonnegative(),
  elevationSource: itineraryElevationSourceSchema,
});
export type ItineraryMetrics = z.infer<typeof itineraryMetricsSchema>;
