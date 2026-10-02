import { Decoder, Stream } from "@garmin/fitsdk";
import {
  DEFAULT_MAX_POINTS,
  TrackFileError,
  type ParseOptions,
  type ParsedTrackFile,
  type ParsedTrackPoint,
} from "./types.js";

const SEMICIRCLE_TO_DEG = 180 / 2 ** 31;
const WINDOW_TOLERANCE_MS = 1000;

interface Rec {
  timestamp?: unknown;
  positionLat?: unknown;
  positionLong?: unknown;
  enhancedAltitude?: unknown;
  altitude?: unknown;
  enhancedSpeed?: unknown;
  speed?: unknown;
  heartRate?: unknown;
  cadence?: unknown;
}

const n = (v: unknown): number | undefined => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
const ms = (v: unknown): number | undefined => (v instanceof Date && !Number.isNaN(+v) ? +v : undefined);

function toPoint(r: Rec): ParsedTrackPoint | undefined {
  const lat = n(r.positionLat);
  const lon = n(r.positionLong);
  if (lat === undefined || lon === undefined) return undefined;
  const p: ParsedTrackPoint = { lat: lat * SEMICIRCLE_TO_DEG, lon: lon * SEMICIRCLE_TO_DEG };
  const set = <K extends keyof ParsedTrackPoint>(k: K, v: ParsedTrackPoint[K]) => {
    if (v !== undefined) p[k] = v;
  };
  set("elevationM", n(r.enhancedAltitude) ?? n(r.altitude));
  set("timestampMs", ms(r.timestamp));
  set("heartRateBpm", n(r.heartRate));
  set("cadenceRpm", n(r.cadence));
  set("speedMs", n(r.enhancedSpeed) ?? n(r.speed));
  return p;
}

function decode(bytes: Uint8Array) {
  const decoder = new Decoder(Stream.fromByteArray(bytes));
  try {
    if (!decoder.isFIT() || !decoder.checkIntegrity()) {
      throw new TrackFileError("invalid_file", "Not a valid FIT file (header or CRC)");
    }
    const { messages, errors } = decoder.read({
      convertDateTimesToDates: true,
      applyScaleAndOffset: true,
      expandComponents: true,
      expandSubFields: true,
    });
    if (errors.length > 0) throw new TrackFileError("invalid_file", `FIT decode error: ${errors[0]?.message}`);
    return messages;
  } catch (e) {
    if (e instanceof TrackFileError) throw e;
    throw new TrackFileError("invalid_file", `FIT decode failure: ${(e as Error).message}`);
  }
}

/** Sport string, e.g. "cycling" or "cycling:mountain" (sub sport kept unless generic). */
function sportOf(session: { sport?: unknown; subSport?: unknown }): string | undefined {
  if (session.sport === undefined || session.sport === null) return undefined;
  const sport = String(session.sport).toLowerCase();
  const sub = session.subSport === undefined || session.subSport === null ? "" : String(session.subSport).toLowerCase();
  return sub && sub !== "generic" ? `${sport}:${sub}` : sport;
}

/** FIT via Garmin's SDK. Multisport files: first session only (ADR-028 §5). */
export function parseFit(bytes: Uint8Array, options: ParseOptions = {}): ParsedTrackFile {
  const max = options.maxPoints ?? DEFAULT_MAX_POINTS;
  const messages = decode(bytes);
  const records = (messages.recordMesgs ?? []) as Rec[];
  const session = messages.sessionMesgs?.[0];

  const startMs = ms(session?.startTime);
  const elapsed = n(session?.totalElapsedTime);
  const endMs = startMs !== undefined && elapsed !== undefined ? startMs + elapsed * 1000 : undefined;
  const inSession = (r: Rec): boolean => {
    const t = ms(r.timestamp);
    if (t === undefined || startMs === undefined || endMs === undefined) return true;
    return t >= startMs - WINDOW_TOLERANCE_MS && t <= endMs + WINDOW_TOLERANCE_MS;
  };

  const points: ParsedTrackPoint[] = [];
  let withoutPosition = 0;
  let samples = 0;
  for (const r of records.filter(inSession)) {
    if (++samples > max) throw new TrackFileError("too_many_points", `More than ${max} points`);
    const p = toPoint(r);
    if (p) points.push(p);
    else withoutPosition++;
  }

  const result: ParsedTrackFile = { format: "fit", points, pointsWithoutPosition: withoutPosition };
  const sport = session ? sportOf(session) : undefined;
  if (sport) result.sport = sport;
  const lastTime = [...points].reverse().find((p) => p.timestampMs !== undefined)?.timestampMs;
  const started = startMs ?? points.find((p) => p.timestampMs !== undefined)?.timestampMs;
  if (started !== undefined) result.startedAtMs = started;
  const ended = endMs ?? lastTime;
  if (ended !== undefined) result.endedAtMs = ended;
  return result;
}
