/** ADR-039 §5: a Segment has one sport among those with a map; never `swim`. */
export const SEGMENT_SPORTS: readonly string[] = ["run", "ride", "walk", "hike"];

/**
 * Default privacy zone radius (ADR-017 `user_profile.privacy_zone_radius_m`): the retro-matching
 * looks for routes within twice it of a Segment's ends, since the stored route is cut around its
 * own start and end (ADR-039 §6, §7).
 */
export const DEFAULT_PRIVACY_ZONE_RADIUS_M = 200;

/**
 * A margin in meters as degrees for an indexed `ST_DWithin` on `geometry(…, 4326)`, overestimated
 * (ADR-039 §6): the scale of a longitude degree at the highest latitude, capped at 80°.
 */
export function marginInDegrees(marginM: number, latitudes: number[]): number {
  const maxLat = Math.min(80, Math.max(...latitudes.map(Math.abs)));
  return marginM / (111_320 * Math.cos((maxLat * Math.PI) / 180));
}
