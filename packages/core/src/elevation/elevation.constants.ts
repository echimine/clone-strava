export interface ElevationModuleOptions {
  /** Per-request timeout, for each provider call. */
  timeoutMs?: number;
  /** Test seam: plays IGN and Open-Meteo in integration tests. */
  fetch?: typeof fetch;
}

export const ELEVATION_OPTIONS = Symbol("ELEVATION_OPTIONS");

/** Where one point's altitude comes from (ADR-030 §3). */
export type ElevationProvider = "ign" | "open_meteo";

export interface PointElevation {
  altitudeM: number;
  source: ElevationProvider;
}

/**
 * A provider failed (network, timeout, HTTP error including `429`,
 * unexpected body): the whole lookup failed and can be retried later.
 */
export class ElevationUnavailableError extends Error {
  constructor(
    readonly provider: ElevationProvider,
    reason: string,
    /** From the provider's `Retry-After`, when it sent one. */
    readonly retryAfterS?: number,
  ) {
    super(`Elevation provider ${provider} unavailable: ${reason}`);
    this.name = "ElevationUnavailableError";
  }
}
