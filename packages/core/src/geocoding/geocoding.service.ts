import { Inject, Injectable, Logger } from "@nestjs/common";
import { formatPlace, type GeocodingFeature } from "./domain/format-place.js";
import { GEOCODING_OPTIONS, type GeocodingModuleOptions } from "./geocoding.constants.js";

const ENDPOINT = "https://api.mapbox.com/search/geocode/v6/reverse";

/**
 * `geocoding` platform module (ADR-029): reverse geocoding of an activity's
 * start point through the Mapbox Geocoding v6 API. Best effort: any
 * failure (no token, timeout, HTTP error) yields `null`, never an error.
 */
@Injectable()
export class GeocodingService {
  private readonly logger = new Logger(GeocodingService.name);

  constructor(@Inject(GEOCODING_OPTIONS) private readonly options: GeocodingModuleOptions) {}

  async reverse(point: { lat: number; lon: number }): Promise<string | null> {
    const { accessToken } = this.options;
    if (!accessToken) {
      return null;
    }
    const url = new URL(ENDPOINT);
    url.search = new URLSearchParams({
      longitude: point.lon.toFixed(5),
      latitude: point.lat.toFixed(5),
      types: "place,locality",
      language: "fr",
      limit: "1",
      permanent: String(this.options.permanent ?? false),
      access_token: accessToken,
    }).toString();

    try {
      const response = await (this.options.fetch ?? fetch)(url, {
        signal: AbortSignal.timeout(this.options.timeoutMs ?? 3000),
      });
      if (!response.ok) {
        this.logger.warn(`Reverse geocoding failed with HTTP ${response.status}`);
        return null;
      }
      const body = (await response.json()) as { features?: GeocodingFeature[] };
      return formatPlace(body.features?.[0]);
    } catch (error) {
      this.logger.warn(`Reverse geocoding failed: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }
}
