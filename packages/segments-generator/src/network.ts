import { haversineDistanceM } from "@repo/geo";
import { frenchName, type OsmWay } from "./osm.js";

/**
 * The networks climbs are searched on (ADR-039 §10): roads open to bikes, streets and paths open
 * to runners, hiking paths up to `sac_scale=demanding_mountain_hiking`.
 */
export type Network = "ride" | "foot" | "hike";

const ROADS = new Set([
  "trunk",
  "trunk_link",
  "primary",
  "primary_link",
  "secondary",
  "secondary_link",
  "tertiary",
  "tertiary_link",
  "unclassified",
  "residential",
  "living_street",
  "road",
]);
/** Only when paved: a `service` road or a `track` is often gravel. */
const PAVED_ONLY = new Set(["service", "track"]);
const PAVED = new Set(["asphalt", "paved", "concrete", "chipseal", "concrete:plates"]);
const FOOT_ONLY = new Set(["footway", "pedestrian", "path", "track", "cycleway", "service", "bridleway"]);
const HIKING_PATHS = new Set(["path", "footway", "track", "bridleway"]);
const HIKING_SAC_SCALES = new Set(["hiking", "mountain_hiking", "demanding_mountain_hiking"]);
const CLOSED = new Set(["no", "private"]);

function closedTo(tags: Record<string, string>, mode: "bicycle" | "foot"): boolean {
  if (tags[mode] === "no") {
    return true;
  }
  return CLOSED.has(tags.access ?? "") && !["yes", "designated", "permissive"].includes(tags[mode] ?? "");
}

function isLine(tags: Record<string, string>): boolean {
  return tags.area !== "yes" && tags.motorroad !== "yes";
}

/** A road a bike may ride (`trunk` to `residential`, paved `service`/`track`, cycleways). */
export function isRideWay(tags: Record<string, string>): boolean {
  const highway = tags.highway ?? "";
  const road =
    ROADS.has(highway) ||
    highway === "cycleway" ||
    (PAVED_ONLY.has(highway) && PAVED.has(tags.surface ?? ""));
  return road && isLine(tags) && !closedTo(tags, "bicycle");
}

/** A street or path a runner may use: no motorway, no expressway. */
export function isFootWay(tags: Record<string, string>): boolean {
  const highway = tags.highway ?? "";
  const open = (ROADS.has(highway) && !highway.startsWith("trunk")) || FOOT_ONLY.has(highway);
  return open && isLine(tags) && !closedTo(tags, "foot");
}

/** A hiking path up to `demanding_mountain_hiking`; beyond is mountaineering. */
export function isHikeWay(tags: Record<string, string>): boolean {
  const sacScale = tags.sac_scale ?? "hiking";
  return (
    HIKING_PATHS.has(tags.highway ?? "") &&
    HIKING_SAC_SCALES.has(sacScale) &&
    isLine(tags) &&
    !closedTo(tags, "foot")
  );
}

export const NETWORK_FILTERS: Record<Network, (tags: Record<string, string>) => boolean> = {
  ride: isRideWay,
  foot: isFootWay,
  hike: isHikeWay,
};

/** The name of a road for « Montée de <route> à <lieu> »: `name:fr`, `name`, else `ref`. */
export function routeNameOf(tags: Record<string, string>): string | null {
  return frenchName(tags) ?? (tags.ref?.trim() || null);
}

/** One way of a chain, in the chain's direction. */
export interface ChainWay {
  way: OsmWay;
  reversed: boolean;
  /** Distance along the chain where the way ends. */
  endM: number;
}

/** Contiguous ways of one road (same name or `ref`), merged at their shared ends. */
export interface Chain {
  ways: ChainWay[];
  coordinates: Array<[number, number]>;
  /** Directions a bike may ride it; on foot, both. */
  forward: boolean;
  backward: boolean;
}

const coordinateKey = ([lon, lat]: [number, number]) => `${lon.toFixed(7)},${lat.toFixed(7)}`;

function onewayOf(tags: Record<string, string>, network: Network): 1 | -1 | 0 {
  if (network !== "ride" || tags["oneway:bicycle"] === "no") {
    return 0;
  }
  const oneway = tags.oneway ?? (tags.junction === "roundabout" ? "yes" : "no");
  if (["yes", "1", "true"].includes(oneway)) {
    return 1;
  }
  return oneway === "-1" ? -1 : 0;
}

/**
 * Chains of a network: the ways of one name (or `ref`, or none) joined where exactly two of them
 * meet, cut at every other junction.
 */
export function buildChains(ways: OsmWay[], network: Network): Chain[] {
  const groups = new Map<string, OsmWay[]>();
  for (const way of ways) {
    if (way.coordinates.length < 2 || !NETWORK_FILTERS[network](way.tags)) {
      continue;
    }
    const key = routeNameOf(way.tags) ?? "";
    groups.set(key, [...(groups.get(key) ?? []), way]);
  }
  return [...groups.values()].flatMap((group) => chainsOfGroup(group, network));
}

function chainsOfGroup(ways: OsmWay[], network: Network): Chain[] {
  const ends = new Map<string, number[]>();
  ways.forEach((way, index) => {
    for (const end of [way.coordinates[0]!, way.coordinates.at(-1)!]) {
      const key = coordinateKey(end);
      ends.set(key, [...(ends.get(key) ?? []), index]);
    }
  });
  const visited = new Set<number>();
  const chains: Chain[] = [];
  /** The other way at `coordinate` when exactly two ways meet there and it is free. */
  const next = (coordinate: [number, number], from: number): number | undefined => {
    const at = ends.get(coordinateKey(coordinate)) ?? [];
    const other = at.length === 2 ? at.find((index) => index !== from) : undefined;
    return other !== undefined && !visited.has(other) ? other : undefined;
  };

  for (let seed = 0; seed < ways.length; seed++) {
    if (visited.has(seed)) {
      continue;
    }
    visited.add(seed);
    const parts: Array<{ index: number; reversed: boolean }> = [{ index: seed, reversed: false }];
    // Forward from the seed's end, then backward from its start.
    for (const direction of ["forward", "backward"] as const) {
      for (;;) {
        const edge = direction === "forward" ? parts.at(-1)! : parts[0]!;
        const coordinates = ways[edge.index]!.coordinates;
        const tip =
          direction === "forward"
            ? edge.reversed ? coordinates[0]! : coordinates.at(-1)!
            : edge.reversed ? coordinates.at(-1)! : coordinates[0]!;
        const other = next(tip, edge.index);
        if (other === undefined) {
          break;
        }
        visited.add(other);
        const startsAtTip = coordinateKey(ways[other]!.coordinates[0]!) === coordinateKey(tip);
        if (direction === "forward") {
          parts.push({ index: other, reversed: !startsAtTip });
        } else {
          parts.unshift({ index: other, reversed: startsAtTip });
        }
      }
    }
    chains.push(toChain(parts.map(({ index, reversed }) => ({ way: ways[index]!, reversed })), network));
  }
  return chains;
}

function toChain(parts: Array<{ way: OsmWay; reversed: boolean }>, network: Network): Chain {
  const coordinates: Array<[number, number]> = [];
  const chainWays: ChainWay[] = [];
  let forward = true;
  let backward = true;
  let lengthM = 0;
  for (const { way, reversed } of parts) {
    const points = reversed ? [...way.coordinates].reverse() : way.coordinates;
    points.forEach((point, i) => {
      const previous = coordinates.at(-1);
      if (i === 0 && previous) {
        return; // the shared end
      }
      if (previous) {
        lengthM += haversineDistanceM({ lon: previous[0], lat: previous[1] }, { lon: point[0], lat: point[1] });
      }
      coordinates.push(point);
    });
    chainWays.push({ way, reversed, endM: lengthM });
    const oneway = onewayOf(way.tags, network) * (reversed ? -1 : 1);
    forward &&= oneway !== -1;
    backward &&= oneway !== 1;
  }
  return { ways: chainWays, coordinates, forward, backward };
}

/** The chain the other way round: a descent becomes a climb. */
export function reverseChain(chain: Chain): Chain {
  const totalM = chain.ways.at(-1)?.endM ?? 0;
  const reversedWays = [...chain.ways].reverse();
  return {
    coordinates: [...chain.coordinates].reverse(),
    ways: reversedWays.map((chainWay, i) => ({
      way: chainWay.way,
      reversed: !chainWay.reversed,
      endM: totalM - (reversedWays[i + 1]?.endM ?? 0),
    })),
    forward: chain.backward,
    backward: chain.forward,
  };
}
