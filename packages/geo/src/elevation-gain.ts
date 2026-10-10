/**
 * Positive elevation gain of a series of altitudes, in meters, with a
 * hysteresis threshold (ADR-030 §3, §7): a climb only starts counting once
 * the altitude has risen `hysteresisM` above the lowest point since the last
 * confirmed descent, and a descent only breaks the climb once it has dropped
 * `hysteresisM` below its highest point. Noise smaller than the threshold is
 * ignored; a confirmed climb is counted in full, from its lowest point.
 */
export function elevationGainM(altitudes: number[], hysteresisM: number): number {
  if (!(hysteresisM >= 0) || !Number.isFinite(hysteresisM)) {
    throw new RangeError(`hysteresisM must be a non-negative finite number, got ${hysteresisM}`);
  }
  if (altitudes.length === 0) {
    return 0;
  }

  let gainM = 0;
  let climbing = false;
  // Lowest point of the current descent, or highest point of the current climb.
  let extremeM = altitudes[0]!;
  for (const altitudeM of altitudes) {
    if (climbing) {
      if (altitudeM > extremeM) {
        gainM += altitudeM - extremeM;
        extremeM = altitudeM;
      } else if (extremeM - altitudeM >= hysteresisM) {
        climbing = false;
        extremeM = altitudeM;
      }
    } else if (altitudeM < extremeM) {
      extremeM = altitudeM;
    } else if (altitudeM - extremeM >= hysteresisM) {
      climbing = true;
      gainM += altitudeM - extremeM;
      extremeM = altitudeM;
    }
  }
  return gainM;
}
