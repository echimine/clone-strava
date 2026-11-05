import { haversineDistanceM, type LonLat } from "@repo/geo";

const M_PER_DEG_LAT = 111_320;

/** Points bucketed in a grid of `cellDeg`, to find the nearest ones without scanning a country. */
export class PointIndex<T> {
  private readonly cells = new Map<string, Array<{ point: LonLat; value: T }>>();

  constructor(private readonly cellDeg = 0.05) {}

  add(point: LonLat, value: T): void {
    const key = this.keyOf(Math.floor(point.lon / this.cellDeg), Math.floor(point.lat / this.cellDeg));
    this.cells.set(key, [...(this.cells.get(key) ?? []), { point, value }]);
  }

  /** The values within `radiusM` of `at`, nearest first. */
  near(at: LonLat, radiusM: number): Array<{ value: T; distanceM: number }> {
    const latSpan = Math.ceil(radiusM / M_PER_DEG_LAT / this.cellDeg);
    const lonScale = Math.max(Math.cos((at.lat * Math.PI) / 180), 0.01);
    const lonSpan = Math.ceil(radiusM / (M_PER_DEG_LAT * lonScale) / this.cellDeg);
    const cx = Math.floor(at.lon / this.cellDeg);
    const cy = Math.floor(at.lat / this.cellDeg);
    const found: Array<{ value: T; distanceM: number }> = [];
    for (let x = cx - lonSpan; x <= cx + lonSpan; x++) {
      for (let y = cy - latSpan; y <= cy + latSpan; y++) {
        for (const entry of this.cells.get(this.keyOf(x, y)) ?? []) {
          const distanceM = haversineDistanceM(at, entry.point);
          if (distanceM <= radiusM) {
            found.push({ value: entry.value, distanceM });
          }
        }
      }
    }
    return found.sort((a, b) => a.distanceM - b.distanceM);
  }

  private keyOf(x: number, y: number): string {
    return `${x}:${y}`;
  }
}
