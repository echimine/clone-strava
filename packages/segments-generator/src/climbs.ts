import { elevationGainM, resampleAlongTrack, trackDistanceM } from "@repo/geo";

/** Altitude in meters at a WGS 84 point, `null` outside the model or on a void. */
export type ElevationAt = (lon: number, lat: number) => number | null;

/** ADR-039 §10: the altitude every ~25 m. */
export const SAMPLE_STEP_M = 25;
/** Samples on each side of the centred moving average (±50 m). */
const SMOOTHING_HALF_WINDOW = 2;
/** A climb goes on through dips shallower than this; a deeper descent ends it. */
const CLIMB_BREAK_M = 10;
/** The hysteresis of the elevation gain (research #14: 2 m stabilises it). */
const GAIN_HYSTERESIS_M = 2;
/** Under 1 % over a step, the start or the top of a climb is flat and trimmed off. */
const FLAT_RISE_M = SAMPLE_STEP_M * 0.01;
/** Span of the maximum grade. */
const MAX_GRADE_SPAN = 4;

export interface Sample {
  lon: number;
  lat: number;
  /** Distance along the chain. */
  distanceM: number;
  /** Smoothed altitude. */
  altitudeM: number;
}

/** A climb from a trough to a summit, with its figures from the elevation model. */
export interface Climb {
  samples: Sample[];
  distanceM: number;
  elevationGainM: number;
  avgGrade: number;
  maxGrade: number;
  minAltitudeM: number;
  maxAltitudeM: number;
  /** Length in meters × average grade in % (ADR-039 §5). */
  score: number;
}

/**
 * The chain sampled every {@link SAMPLE_STEP_M} with smoothed altitudes; split where the model has
 * a void, since nothing can be measured there.
 */
export function profilesOf(coordinates: Array<[number, number]>, elevationAt: ElevationAt): Sample[][] {
  const resampled = resampleAlongTrack(
    coordinates.map(([lon, lat]) => ({ lon, lat })),
    SAMPLE_STEP_M,
  );
  const runs: Array<Array<Omit<Sample, "altitudeM"> & { rawM: number }>> = [[]];
  resampled.forEach((point, i) => {
    const rawM = elevationAt(point.lon, point.lat);
    if (rawM === null) {
      runs.push([]);
      return;
    }
    const distanceM = i === resampled.length - 1 ? lastDistanceM(coordinates) : i * SAMPLE_STEP_M;
    runs.at(-1)!.push({ lon: point.lon, lat: point.lat, distanceM, rawM });
  });
  return runs
    .filter((run) => run.length >= 2)
    .map((run) =>
      run.map(({ rawM: _rawM, ...sample }, i) => {
        const window = run.slice(Math.max(0, i - SMOOTHING_HALF_WINDOW), i + SMOOTHING_HALF_WINDOW + 1);
        return { ...sample, altitudeM: window.reduce((sum, s) => sum + s.rawM, 0) / window.length };
      }),
    );
}

function lastDistanceM(coordinates: Array<[number, number]>): number {
  return trackDistanceM(coordinates.map(([lon, lat]) => ({ lon, lat })));
}

/**
 * Trough → summit pairs of a profile (ADR-039 §10): a climb starts at the lowest point before a
 * rise and goes on, through dips under {@link CLIMB_BREAK_M}, to its highest point. Flat starts
 * and tops are trimmed off.
 */
export function detectClimbs(profile: Sample[]): Climb[] {
  const altitudes = profile.map((sample) => sample.altitudeM);
  const ranges: Array<[number, number]> = [];
  let climbing = false;
  let low = 0;
  let high = 0;
  altitudes.forEach((altitude, i) => {
    if (!climbing) {
      if (altitude < altitudes[low]!) {
        low = i;
      } else if (altitude - altitudes[low]! >= CLIMB_BREAK_M) {
        climbing = true;
        high = i;
      }
    } else if (altitude > altitudes[high]!) {
      high = i;
    } else if (altitudes[high]! - altitude >= CLIMB_BREAK_M) {
      ranges.push([low, high]);
      climbing = false;
      low = i;
    }
  });
  if (climbing) {
    ranges.push([low, high]);
  }
  return ranges.map(([start, end]) => {
    while (start < end - 1 && altitudes[start + 1]! - altitudes[start]! < FLAT_RISE_M) {
      start++;
    }
    while (end > start + 1 && altitudes[end]! - altitudes[end - 1]! < FLAT_RISE_M) {
      end--;
    }
    return climbOf(profile.slice(start, end + 1));
  });
}

function climbOf(samples: Sample[]): Climb {
  const altitudes = samples.map((sample) => sample.altitudeM);
  const distanceM = samples.at(-1)!.distanceM - samples[0]!.distanceM;
  const avgGrade = ((altitudes.at(-1)! - altitudes[0]!) / distanceM) * 100;
  let maxGrade = avgGrade;
  for (let i = 0; i + MAX_GRADE_SPAN < samples.length; i++) {
    const rise = altitudes[i + MAX_GRADE_SPAN]! - altitudes[i]!;
    const run = samples[i + MAX_GRADE_SPAN]!.distanceM - samples[i]!.distanceM;
    maxGrade = Math.max(maxGrade, (rise / run) * 100);
  }
  return {
    samples,
    distanceM,
    elevationGainM: elevationGainM(altitudes, GAIN_HYSTERESIS_M),
    avgGrade,
    maxGrade,
    minAltitudeM: Math.min(...altitudes),
    maxAltitudeM: Math.max(...altitudes),
    score: distanceM * avgGrade,
  };
}
