/** Subset of a Mapbox Geocoding v6 feature used to name a place (ADR-029). */
export interface GeocodingFeature {
  properties?: {
    name?: string;
    context?: {
      place?: { name?: string };
      locality?: { name?: string };
      region?: { name?: string };
      country?: { name?: string };
    };
  };
}

/** `"{place}, {region}"` (e.g. "Annecy, Haute-Savoie"), falling back to the country, then the place alone. */
export function formatPlace(feature: GeocodingFeature | undefined): string | null {
  const properties = feature?.properties;
  const context = properties?.context;
  const place = context?.place?.name ?? context?.locality?.name ?? properties?.name;
  if (!place) {
    return null;
  }
  const area = context?.region?.name ?? context?.country?.name;
  return area && area !== place ? `${place}, ${area}` : place;
}
