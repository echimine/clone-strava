export interface GeocodingModuleOptions {
  /** Server-side Mapbox secret token; without it, geocoding is disabled (returns `null`). */
  accessToken?: string;
  /** `permanent=true`: required by Mapbox's terms to store results (ADR-029). */
  permanent?: boolean;
  timeoutMs?: number;
  /** Test seam. */
  fetch?: typeof fetch;
}

export const GEOCODING_OPTIONS = Symbol("GEOCODING_OPTIONS");
