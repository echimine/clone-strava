import type { LonLat } from "@repo/geo";
import { frenchName, type OsmNode } from "./osm.js";
import { PointIndex } from "./point-index.js";

/** A summit closer than this to the top of a climb is where it goes. */
export const SUMMIT_RADIUS_M = 150;
/** The place a climb starts from or arrives at is at most this far away. */
const PLACE_RADIUS_M = 5_000;
/** A run Segment is « urban » when it starts this close to a town or a district. */
export const URBAN_RADIUS_M = 1_500;
/** Like an athlete's Segment (ADR-039 §5). */
const NAME_LENGTH = { min: 3, max: 60 };

const PLACES = new Set(["city", "town", "village", "hamlet", "suburb", "neighbourhood", "quarter", "locality"]);
const URBAN_PLACES = new Set(["city", "town", "suburb", "neighbourhood", "quarter"]);

const FEMININE = new Set(["rue", "route", "avenue", "côte", "allée", "impasse", "place", "voie", "montée", "rampe", "promenade", "corniche"]);
const MASCULINE = new Set(["chemin", "boulevard", "sentier", "passage", "quai", "cours", "col", "pont", "faubourg"]);

export interface NamedPlace {
  name: string;
  /** OSM `place=*`. */
  kind: string;
}

/** The named passes, summits and places of an extract, indexed for the naming. */
export class Gazetteer {
  private readonly passes = new PointIndex<string>();
  private readonly peaks = new PointIndex<string>();
  private readonly places = new PointIndex<NamedPlace>();

  constructor(nodes: OsmNode[]) {
    for (const node of nodes) {
      const name = frenchName(node.tags);
      if (!name) {
        continue;
      }
      const point = { lon: node.coordinate[0], lat: node.coordinate[1] };
      if (node.tags.mountain_pass === "yes") {
        this.passes.add(point, name);
      }
      if (node.tags.natural === "peak") {
        this.peaks.add(point, name);
      }
      if (PLACES.has(node.tags.place ?? "")) {
        this.places.add(point, { name, kind: node.tags.place! });
      }
    }
  }

  /** The named pass at the top of a climb. */
  passAt(top: LonLat): string | null {
    return this.passes.near(top, SUMMIT_RADIUS_M)[0]?.value ?? null;
  }

  /** The named summit at the top of a climb (ADR-039 §10: a hike goes to one). */
  peakAt(top: LonLat): string | null {
    return this.peaks.near(top, SUMMIT_RADIUS_M)[0]?.value ?? null;
  }

  placeNear(point: LonLat): NamedPlace | null {
    return this.places.near(point, PLACE_RADIUS_M)[0]?.value ?? null;
  }

  /** The town or district a short urban climb starts in, if any. */
  urbanPlaceNear(point: LonLat): NamedPlace | null {
    return this.places.near(point, URBAN_RADIUS_M).find(({ value }) => URBAN_PLACES.has(value.kind))?.value ?? null;
  }
}

/**
 * ADR-039 §10, in French: « <col ou sommet> depuis <lieu du départ> » when the climb tops out at a
 * named pass or summit, else « Montée de <route> à <lieu de l'arrivée> ». `null` without a usable
 * name: no Segment then.
 */
export function segmentName(
  input: { summit: string | null; route: string | null; start: LonLat; top: LonLat },
  gazetteer: Gazetteer,
): string | null {
  let name: string | null = null;
  if (input.summit) {
    const from = gazetteer.placeNear(input.start);
    name = from && from.name !== input.summit ? `${input.summit} depuis ${from.name}` : input.summit;
  } else if (input.route) {
    const to = gazetteer.placeNear(input.top);
    name = to ? `Montée ${ofRoute(input.route)} à ${to.name}` : null;
  }
  return name !== null && name.length >= NAME_LENGTH.min && name.length <= NAME_LENGTH.max ? name : null;
}

/** « de la D 902 », « de la rue de la Côte », « du chemin des Vignes », « de l'avenue Foch ». */
function ofRoute(route: string): string {
  if (/^[A-Z]{1,3} ?\d/.test(route)) {
    return `de la ${route}`;
  }
  const [first = "", ...rest] = route.split(" ");
  const word = first.toLowerCase();
  const tail = rest.length > 0 ? ` ${rest.join(" ")}` : "";
  if (FEMININE.has(word) || MASCULINE.has(word)) {
    if (/^[aeiouyàâéèêîôû]/i.test(word)) {
      return `de l'${word}${tail}`;
    }
    return FEMININE.has(word) ? `de la ${word}${tail}` : `du ${word}${tail}`;
  }
  return /^[aeiouyàâéèêîôû]/i.test(route) ? `d'${route}` : `de ${route}`;
}
