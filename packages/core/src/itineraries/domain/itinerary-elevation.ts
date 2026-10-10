import type { ItineraryElevationSource } from "@repo/contracts";

/**
 * The Itinerary's elevation source from its points' sources (ADR-030 §3):
 * `ign` if all come from IGN, `open_meteo` if all come from Open-Meteo,
 * `mixed` otherwise.
 */
export function itineraryElevationSource(sources: readonly ("ign" | "open_meteo")[]): ItineraryElevationSource {
  const hasIgn = sources.includes("ign");
  const hasOpenMeteo = sources.includes("open_meteo");
  if (hasIgn && hasOpenMeteo) {
    return "mixed";
  }
  return hasOpenMeteo ? "open_meteo" : "ign";
}

/**
 * Distances and gains are exposed to the decimeter: a `real` column gives
 * back exactly this value, so a preview equals what a save stores.
 */
export function roundToDecimeter(valueM: number): number {
  return Math.round(valueM * 10) / 10;
}
