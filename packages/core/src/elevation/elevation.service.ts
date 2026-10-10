import { Inject, Injectable } from "@nestjs/common";
import type { LonLat } from "@repo/geo";
import {
  ELEVATION_OPTIONS,
  ElevationUnavailableError,
  type ElevationModuleOptions,
  type ElevationProvider,
  type PointElevation,
} from "./elevation.constants.js";

const IGN_ENDPOINT = "https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json";
/** RGE ALTI, France and overseas departments, 1 m DTM. */
const IGN_RESOURCE = "ign_rge_alti_wld";
const IGN_MAX_POINTS = 5000;
/** IGN's altitude for a point outside its coverage. */
const IGN_NO_DATA = -99999;

const OPEN_METEO_ENDPOINT = "https://api.open-meteo.com/v1/elevation";
const OPEN_METEO_MAX_POINTS = 100;

const DEFAULT_TIMEOUT_MS = 10_000;

/**
 * `elevation` platform module (ADR-030 §3, §4): one altitude per point, in
 * order. IGN RGE ALTI first; points it does not cover (`-99999`) go to
 * Open-Meteo (Copernicus GLO-90). Batches are sent one after the other
 * (IGN allows 5 requests/s per IP, shared by the whole API). Any provider
 * failure, `429` included, throws `ElevationUnavailableError`: the caller
 * cannot get a partial answer.
 */
@Injectable()
export class ElevationService {
  constructor(@Inject(ELEVATION_OPTIONS) private readonly options: ElevationModuleOptions) {}

  async getElevations(points: LonLat[]): Promise<PointElevation[]> {
    const results: (PointElevation | undefined)[] = [];
    for (let start = 0; start < points.length; start += IGN_MAX_POINTS) {
      const altitudes = await this.fetchIgn(points.slice(start, start + IGN_MAX_POINTS));
      for (const altitudeM of altitudes) {
        results.push(altitudeM <= IGN_NO_DATA ? undefined : { altitudeM, source: "ign" });
      }
    }

    const uncovered = results.flatMap((result, index) => (result ? [] : [index]));
    for (let start = 0; start < uncovered.length; start += OPEN_METEO_MAX_POINTS) {
      const indexes = uncovered.slice(start, start + OPEN_METEO_MAX_POINTS);
      const altitudes = await this.fetchOpenMeteo(indexes.map((index) => points[index]!));
      indexes.forEach((index, i) => {
        results[index] = { altitudeM: altitudes[i]!, source: "open_meteo" };
      });
    }
    return results as PointElevation[];
  }

  private async fetchIgn(points: LonLat[]): Promise<number[]> {
    // IGN wants booleans as strings ("true"/"false") in its JSON body.
    const body = {
      lon: points.map((point) => point.lon.toFixed(6)).join("|"),
      lat: points.map((point) => point.lat.toFixed(6)).join("|"),
      resource: IGN_RESOURCE,
      delimiter: "|",
      zonly: "true",
      measures: "false",
    };
    const json = await this.request("ign", IGN_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return altitudesOf("ign", (json as { elevations?: unknown }).elevations, points.length);
  }

  private async fetchOpenMeteo(points: LonLat[]): Promise<number[]> {
    const url = new URL(OPEN_METEO_ENDPOINT);
    url.search = new URLSearchParams({
      latitude: points.map((point) => point.lat.toFixed(6)).join(","),
      longitude: points.map((point) => point.lon.toFixed(6)).join(","),
    }).toString();
    const json = await this.request("open_meteo", url, { method: "GET" });
    return altitudesOf("open_meteo", (json as { elevation?: unknown }).elevation, points.length);
  }

  private async request(provider: ElevationProvider, url: string | URL, init: RequestInit): Promise<unknown> {
    let response: Response;
    try {
      response = await (this.options.fetch ?? fetch)(url, {
        ...init,
        signal: AbortSignal.timeout(this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS),
      });
    } catch (error) {
      throw new ElevationUnavailableError(provider, error instanceof Error ? error.message : String(error));
    }
    if (!response.ok) {
      throw new ElevationUnavailableError(provider, `HTTP ${response.status}`, retryAfterOf(response));
    }
    try {
      return await response.json();
    } catch {
      throw new ElevationUnavailableError(provider, "invalid JSON body");
    }
  }
}

function altitudesOf(provider: ElevationProvider, value: unknown, expected: number): number[] {
  if (!Array.isArray(value) || value.length !== expected || !value.every((v) => Number.isFinite(v))) {
    throw new ElevationUnavailableError(provider, "unexpected response body");
  }
  return value as number[];
}

/** `Retry-After` in seconds (only the delta-seconds form). */
function retryAfterOf(response: Response): number | undefined {
  const seconds = Number(response.headers.get("retry-after"));
  return Number.isInteger(seconds) && seconds > 0 ? seconds : undefined;
}
