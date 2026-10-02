import { asArray, asNode, findDeep, num, parseXml, text, timeMs, type XmlNode } from "./xml.js";
import {
  DEFAULT_MAX_POINTS,
  TrackFileError,
  type ParseOptions,
  type ParsedTrackFile,
  type ParsedTrackPoint,
} from "./types.js";

const ARRAY_TAGS: ReadonlySet<string> = new Set(["trk", "trkseg", "trkpt"]);

function toPoint(pt: XmlNode): ParsedTrackPoint | undefined {
  const lat = num(pt["@_lat"]);
  const lon = num(pt["@_lon"]);
  if (lat === undefined || lon === undefined) return undefined;
  const point: ParsedTrackPoint = { lat, lon };
  const ext = asNode(pt["extensions"]);
  const set = <K extends keyof ParsedTrackPoint>(k: K, v: ParsedTrackPoint[K]) => {
    if (v !== undefined) point[k] = v;
  };
  set("elevationM", num(pt["ele"]));
  set("timestampMs", timeMs(pt["time"]));
  // Garmin gpxtpx:TrackPointExtension; namespace prefixes are stripped by the parser.
  set("heartRateBpm", num(findDeep(ext, "hr")));
  set("cadenceRpm", num(findDeep(ext, "cad")));
  return point;
}

/** GPX 1.0/1.1: every trk/trkseg/trkpt; rte and wpt are ignored (ADR-028 §5). */
export function parseGpx(bytes: Uint8Array, options: ParseOptions = {}): ParsedTrackFile {
  const max = options.maxPoints ?? DEFAULT_MAX_POINTS;
  const root = asNode(parseXml(bytes, ARRAY_TAGS)["gpx"]);
  if (!root) throw new TrackFileError("invalid_file", "Missing <gpx> root element");

  const trks = asArray(root["trk"]);
  const points: ParsedTrackPoint[] = [];
  let withoutPosition = 0;
  let samples = 0;
  for (const seg of trks.flatMap((t) => asArray(t["trkseg"]))) {
    for (const pt of asArray(seg["trkpt"])) {
      if (++samples > max) throw new TrackFileError("too_many_points", `More than ${max} points`);
      const p = toPoint(pt);
      if (p) points.push(p);
      else withoutPosition++;
    }
  }

  const result: ParsedTrackFile = { format: "gpx", points, pointsWithoutPosition: withoutPosition };
  const name = text(trks[0]?.["name"]) ?? text(asNode(root["metadata"])?.["name"]);
  const sport = text(trks[0]?.["type"])?.toLowerCase();
  if (name) result.name = name;
  if (sport) result.sport = sport;
  const times = points.map((p) => p.timestampMs).filter((t): t is number => t !== undefined);
  if (times.length > 0) {
    result.startedAtMs = times[0];
    result.endedAtMs = times[times.length - 1];
  }
  return result;
}
