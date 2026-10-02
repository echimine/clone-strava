import { asArray, asNode, findDeep, num, parseXml, timeMs, type XmlNode } from "./xml.js";
import {
  DEFAULT_MAX_POINTS,
  TrackFileError,
  type ParseOptions,
  type ParsedTrackFile,
  type ParsedTrackPoint,
} from "./types.js";

const ARRAY_TAGS: ReadonlySet<string> = new Set(["Activity", "Lap", "Track", "Trackpoint"]);

function toPoint(tp: XmlNode): ParsedTrackPoint | undefined {
  const pos = asNode(tp["Position"]);
  const lat = num(pos?.["LatitudeDegrees"]);
  const lon = num(pos?.["LongitudeDegrees"]);
  if (lat === undefined || lon === undefined) return undefined;
  const point: ParsedTrackPoint = { lat, lon };
  const set = <K extends keyof ParsedTrackPoint>(k: K, v: ParsedTrackPoint[K]) => {
    if (v !== undefined) point[k] = v;
  };
  const ext = asNode(tp["Extensions"]);
  set("elevationM", num(tp["AltitudeMeters"]));
  set("timestampMs", timeMs(tp["Time"]));
  set("heartRateBpm", num(asNode(tp["HeartRateBpm"])?.["Value"]));
  set("cadenceRpm", num(tp["Cadence"]) ?? num(findDeep(ext, "RunCadence")));
  set("speedMs", num(findDeep(ext, "Speed")));
  return point;
}

/** TCX: all Lap/Track/Trackpoint of the first Activity (ADR-028 §5). */
export function parseTcx(bytes: Uint8Array, options: ParseOptions = {}): ParsedTrackFile {
  const max = options.maxPoints ?? DEFAULT_MAX_POINTS;
  const root = asNode(parseXml(bytes, ARRAY_TAGS)["TrainingCenterDatabase"]);
  if (!root) throw new TrackFileError("invalid_file", "Missing <TrainingCenterDatabase> root");

  const activity = asArray(asNode(root["Activities"])?.["Activity"])[0];
  const laps = activity ? asArray(activity["Lap"]) : [];
  const points: ParsedTrackPoint[] = [];
  let withoutPosition = 0;
  let samples = 0;
  for (const tp of laps.flatMap((l) => asArray(l["Track"])).flatMap((t) => asArray(t["Trackpoint"]))) {
    if (++samples > max) throw new TrackFileError("too_many_points", `More than ${max} points`);
    const p = toPoint(tp);
    if (p) points.push(p);
    else withoutPosition++;
  }

  const result: ParsedTrackFile = { format: "tcx", points, pointsWithoutPosition: withoutPosition };
  const sport = activity?.["@_Sport"];
  if (typeof sport === "string" && sport) result.sport = sport.toLowerCase();
  const firstTime = points.find((p) => p.timestampMs !== undefined)?.timestampMs;
  const lastTime = [...points].reverse().find((p) => p.timestampMs !== undefined)?.timestampMs;
  const start = timeMs(laps[0]?.["@_StartTime"]) ?? firstTime;
  if (start !== undefined) result.startedAtMs = start;
  if (lastTime !== undefined) result.endedAtMs = lastTime;
  return result;
}
