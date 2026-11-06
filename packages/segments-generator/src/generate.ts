import { createHash } from "node:crypto";
import type { NervoSegmentLine, NervoSegmentSport } from "@repo/contracts";
import {
  climbCategory,
  isSameSegment,
  SEGMENT_MAX_LENGTH_M,
  SEGMENT_MIN_ENDS_APART_M,
  SEGMENT_MIN_LENGTH_M,
} from "@repo/core/segments/domain";
import { haversineDistanceM, type LonLat } from "@repo/geo";
import { detectClimbs, profilesOf, type Climb, type ElevationAt } from "./climbs.js";
import { Gazetteer, segmentName } from "./naming.js";
import { buildChains, isFootWay, reverseChain, routeNameOf, type Chain, type Network } from "./network.js";
import type { OsmData } from "./osm.js";
import { PointIndex } from "./point-index.js";

interface Rules {
  minLengthM: number;
  maxLengthM: number;
  minGrade: number;
  maxGrade: number;
  /** Lowest distance × grade; 0 for a hike, whose summit is the point. */
  minScore: number;
}

/**
 * Rules per sport (ADR-039 §5, §10): the length and loop rules of an athlete's Segment
 * (`packages/core`), then the climb filter.
 */
const RULES = {
  ride: { minLengthM: SEGMENT_MIN_LENGTH_M.ride!, maxLengthM: SEGMENT_MAX_LENGTH_M, minGrade: 3, maxGrade: 20, minScore: 8_000 },
  /** Short urban climbs only; road climbs come from the ride ones. */
  urbanRun: { minLengthM: SEGMENT_MIN_LENGTH_M.run!, maxLengthM: 3_000, minGrade: 3, maxGrade: 25, minScore: 1_500 },
  hike: { minLengthM: SEGMENT_MIN_LENGTH_M.hike!, maxLengthM: SEGMENT_MAX_LENGTH_M, minGrade: 3, maxGrade: 60, minScore: 0 },
} satisfies Record<string, Rules>;
/** « Quelques » urban run climbs: the best ones per town or district. */
const URBAN_RUN_CLIMBS_PER_PLACE = 3;

interface Candidate {
  sport: NervoSegmentSport;
  name: string;
  climb: Climb;
  wayIds: string[];
  footAccessible: boolean;
}

/**
 * The Nervo Segments of an OSM extract (ADR-039 §10): roads and paths, the altitude every ~25 m
 * smoothed with hysteresis, trough → summit climbs, the per-sport filter, the French name, and
 * the both-ways duplicate test of `packages/core`. `walk` gets none.
 */
export function generateSegments(osm: OsmData, elevationAt: ElevationAt): NervoSegmentLine[] {
  const gazetteer = new Gazetteer(osm.nodes);
  const climbsOf = (network: Network) =>
    buildChains(osm.ways, network).flatMap((chain) =>
      [chain.forward ? chain : null, chain.backward ? reverseChain(chain) : null]
        .filter((oriented): oriented is Chain => oriented !== null)
        .flatMap((oriented) =>
          profilesOf(oriented.coordinates, elevationAt).flatMap((profile) =>
            detectClimbs(profile).map((climb) => ({ climb, chain: oriented })),
          ),
        ),
    );

  const ride: Candidate[] = [];
  for (const { climb, chain } of climbsOf("ride")) {
    if (!passes(climb, RULES.ride)) {
      continue;
    }
    const ways = waysOf(chain, climb);
    const name = segmentName(
      { summit: gazetteer.passAt(topOf(climb)), route: routeAtTop(chain, climb), start: startOf(climb), top: topOf(climb) },
      gazetteer,
    );
    if (name) {
      ride.push({
        sport: "ride",
        name,
        climb,
        wayIds: ways.map((way) => way.id),
        footAccessible: ways.every((way) => isFootWay(way.tags)),
      });
    }
  }

  const urbanRun: Array<Candidate & { place: string }> = [];
  for (const { climb, chain } of climbsOf("foot")) {
    const place = gazetteer.urbanPlaceNear(startOf(climb));
    if (!place || !passes(climb, RULES.urbanRun)) {
      continue;
    }
    const name = segmentName(
      { summit: gazetteer.passAt(topOf(climb)), route: routeAtTop(chain, climb), start: startOf(climb), top: topOf(climb) },
      gazetteer,
    );
    if (name) {
      urbanRun.push({ sport: "run", name, climb, wayIds: waysOf(chain, climb).map((way) => way.id), footAccessible: true, place: place.name });
    }
  }

  const hike: Candidate[] = [];
  for (const { climb, chain } of climbsOf("hike")) {
    const peak = gazetteer.peakAt(topOf(climb));
    if (!peak || !passes(climb, RULES.hike)) {
      continue;
    }
    const name = segmentName({ summit: peak, route: null, start: startOf(climb), top: topOf(climb) }, gazetteer);
    if (name) {
      hike.push({ sport: "hike", name, climb, wayIds: waysOf(chain, climb).map((way) => way.id), footAccessible: true });
    }
  }

  const run = [
    ...ride.filter((candidate) => candidate.footAccessible).map((candidate) => ({ ...candidate, sport: "run" as const })),
    ...capPerPlace(urbanRun),
  ];
  return [...withoutDuplicates(ride), ...withoutDuplicates(run), ...withoutDuplicates(hike)]
    .map(toLine)
    .sort((a, b) => a.sport.localeCompare(b.sport) || a.sourceKey.localeCompare(b.sourceKey));
}

function passes(climb: Climb, rules: Rules): boolean {
  return (
    climb.distanceM >= rules.minLengthM &&
    climb.distanceM <= rules.maxLengthM &&
    climb.avgGrade >= rules.minGrade &&
    climb.avgGrade <= rules.maxGrade &&
    climb.score >= rules.minScore &&
    haversineDistanceM(startOf(climb), topOf(climb)) >= SEGMENT_MIN_ENDS_APART_M
  );
}

const startOf = (climb: Climb): LonLat => climb.samples[0]!;
const topOf = (climb: Climb): LonLat => climb.samples.at(-1)!;

/** The ways the climb runs on, in its direction. */
function waysOf(chain: Chain, climb: Climb) {
  const fromM = climb.samples[0]!.distanceM;
  const toM = climb.samples.at(-1)!.distanceM;
  let wayStartM = 0;
  const ways = [];
  for (const chainWay of chain.ways) {
    if (chainWay.endM > fromM && wayStartM < toM) {
      ways.push(chainWay.way);
    }
    wayStartM = chainWay.endM;
  }
  return ways;
}

/** The road at the top, for « Montée de <route> ». */
function routeAtTop(chain: Chain, climb: Climb): string | null {
  const ways = waysOf(chain, climb);
  return ways.length > 0 ? routeNameOf(ways.at(-1)!.tags) : null;
}

function capPerPlace(candidates: Array<Candidate & { place: string }>): Candidate[] {
  const perPlace = new Map<string, Candidate[]>();
  for (const candidate of [...candidates].sort((a, b) => b.climb.score - a.climb.score)) {
    const kept = perPlace.get(candidate.place) ?? [];
    if (kept.length < URBAN_RUN_CLIMBS_PER_PLACE && !kept.some((other) => sameClimb(other, candidate))) {
      perPlace.set(candidate.place, [...kept, candidate]);
    }
  }
  return [...perPlace.values()].flat();
}

const pathOf = (candidate: Candidate): LonLat[] => candidate.climb.samples;

function sameClimb(a: Candidate, b: Candidate): boolean {
  return isSameSegment(pathOf(a), pathOf(b));
}

/**
 * The internal duplicate test (ADR-039 §10): `matchSegment` both ways, through `isSameSegment`,
 * only between climbs whose ends are close; the highest score is kept.
 */
function withoutDuplicates(candidates: Candidate[]): Candidate[] {
  const byStart = new PointIndex<Candidate>(0.005);
  const kept: Candidate[] = [];
  const sorted = [...candidates].sort((a, b) => b.climb.score - a.climb.score || sourceKeyOf(a).localeCompare(sourceKeyOf(b)));
  for (const candidate of sorted) {
    const duplicate = byStart
      .near(startOf(candidate.climb), 200)
      .some(
        ({ value }) =>
          haversineDistanceM(topOf(value.climb), topOf(candidate.climb)) <= 200 && sameClimb(value, candidate),
      );
    if (!duplicate) {
      kept.push(candidate);
      byStart.add(startOf(candidate.climb), candidate);
    }
  }
  return kept;
}

/** Stable across runs on the same data: the OSM ways, in order, and the rounded ends. */
function sourceKeyOf(candidate: Candidate): string {
  const round = (point: LonLat) => `${point.lon.toFixed(4)},${point.lat.toFixed(4)}`;
  const digest = createHash("sha256")
    .update(`${candidate.wayIds.join(",")}|${round(startOf(candidate.climb))}|${round(topOf(candidate.climb))}`)
    .digest("hex")
    .slice(0, 24);
  return `osm:${candidate.sport}:${digest}`;
}

const round = (value: number, decimals: number) => Number(value.toFixed(decimals));

function toLine(candidate: Candidate): NervoSegmentLine {
  const { climb } = candidate;
  return {
    sourceKey: sourceKeyOf(candidate),
    sport: candidate.sport,
    name: candidate.name,
    path: climb.samples.map((s) => [round(s.lon, 6), round(s.lat, 6), round(s.altitudeM, 1)] as [number, number, number]),
    distanceM: round(climb.distanceM, 1),
    elevationGainM: round(climb.elevationGainM, 1),
    avgGrade: round(climb.avgGrade, 1),
    maxGrade: round(climb.maxGrade, 1),
    minAltitudeM: round(climb.minAltitudeM, 1),
    maxAltitudeM: round(climb.maxAltitudeM, 1),
    climbCategory: climbCategory(climb.distanceM, climb.avgGrade),
  };
}
