/** Point in WGS 84 degrees. */
export interface LonLat {
  lat: number;
  lon: number;
}

/** Point in WGS 84 degrees with an optional altitude in meters. */
export interface GeoPoint extends LonLat {
  elevationM?: number;
}
