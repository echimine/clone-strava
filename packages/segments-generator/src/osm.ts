import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { createGunzip } from "node:zlib";

/** An OSM way as `osmium export` writes it: its tags and its LineString in WGS 84. */
export interface OsmWay {
  /** `w<id>` (`--add-unique-id=type_id`). */
  id: string;
  tags: Record<string, string>;
  coordinates: Array<[number, number]>;
}

/** An OSM node with tags: a pass, a summit, a place. */
export interface OsmNode {
  id: string;
  tags: Record<string, string>;
  coordinate: [number, number];
}

export interface OsmData {
  ways: OsmWay[];
  nodes: OsmNode[];
}

/**
 * One record of `osmium export -f geojsonseq --add-unique-id=type_id`: a node becomes a Point, a
 * way a LineString. Anything else (areas, relations) is left out: no Segment comes from it.
 */
export function osmFeatureOf(line: string): OsmWay | OsmNode | null {
  // RFC 8142 puts a record separator before each record; `osmium` does by default.
  const text = line.replace(/^\x1e/, "").trim();
  if (text === "") {
    return null;
  }
  const feature = JSON.parse(text) as {
    id?: string | number;
    geometry?: { type: string; coordinates: unknown };
    properties?: Record<string, unknown>;
  };
  const id = String(feature.id ?? feature.properties?.["@id"] ?? "");
  const tags = Object.fromEntries(
    Object.entries(feature.properties ?? {})
      .filter(([key, value]) => !key.startsWith("@") && typeof value === "string")
      .map(([key, value]) => [key, value as string]),
  );
  if (feature.geometry?.type === "Point" && Object.keys(tags).length > 0) {
    return { id, tags, coordinate: feature.geometry.coordinates as [number, number] };
  }
  if (feature.geometry?.type === "LineString") {
    return { id, tags, coordinates: feature.geometry.coordinates as Array<[number, number]> };
  }
  return null;
}

/** Reads a GeoJSON text sequence, gzipped or not, line by line (a country does not fit in a string). */
export async function readOsmGeoJsonSeq(path: string): Promise<OsmData> {
  const input = createReadStream(path);
  const lines = createInterface({
    input: path.endsWith(".gz") ? input.pipe(createGunzip()) : input,
    crlfDelay: Infinity,
  });
  const data: OsmData = { ways: [], nodes: [] };
  for await (const line of lines) {
    const feature = osmFeatureOf(line);
    if (feature && "coordinates" in feature) {
      data.ways.push(feature);
    } else if (feature) {
      data.nodes.push(feature);
    }
  }
  return data;
}

/** The French name of a feature (ADR-039 §10): `name:fr`, else `name`. */
export function frenchName(tags: Record<string, string>): string | null {
  const name = (tags["name:fr"] ?? tags.name ?? "").trim();
  return name === "" ? null : name;
}
