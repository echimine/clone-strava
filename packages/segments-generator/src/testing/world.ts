import type { OsmData, OsmNode, OsmWay } from "../osm.js";

const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;

/**
 * A small synthetic world for the tests, in meters east (`x`) and north (`y`) of an origin in the
 * Alps: OSM ways and nodes built from meters, and an elevation model written as a function of
 * meters.
 */
export function world(origin = { lon: 6, lat: 45 }) {
  const mPerDegLon = M_PER_DEG_LAT * Math.cos((origin.lat * Math.PI) / 180);
  const toLonLat = (x: number, y: number): [number, number] => [
    origin.lon + x / mPerDegLon,
    origin.lat + y / M_PER_DEG_LAT,
  ];
  const toXy = (lon: number, lat: number) => ({
    x: (lon - origin.lon) * mPerDegLon,
    y: (lat - origin.lat) * M_PER_DEG_LAT,
  });
  let nextId = 1;
  const ways: OsmWay[] = [];
  const nodes: OsmNode[] = [];
  return {
    toLonLat,
    toXy,
    /** A way through these points, in meters. */
    way(tags: Record<string, string>, ...points: Array<[number, number]>): OsmWay {
      const way = { id: `w${nextId++}`, tags, coordinates: points.map(([x, y]) => toLonLat(x, y)) };
      ways.push(way);
      return way;
    },
    node(tags: Record<string, string>, x: number, y: number): OsmNode {
      const node = { id: `n${nextId++}`, tags, coordinate: toLonLat(x, y) };
      nodes.push(node);
      return node;
    },
    osm(): OsmData {
      return { ways: [...ways], nodes: [...nodes] };
    },
    /** An elevation model from a function of meters. */
    elevation(altitudeAt: (x: number, y: number) => number | null) {
      return (lon: number, lat: number) => {
        const { x, y } = toXy(lon, lat);
        return altitudeAt(x, y);
      };
    },
  };
}

/** Rises from `fromM` at `gradePct`, over `lengthM`, flat elsewhere. */
export function ramp(fromM: number, lengthM: number, gradePct: number, baseM = 1000) {
  return (t: number) => baseM + (gradePct / 100) * Math.min(Math.max(t - fromM, 0), lengthM);
}
