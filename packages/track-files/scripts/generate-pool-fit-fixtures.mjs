// One-off generator for fixtures/pool-25m.fit and fixtures/pool-25yd.fit (ADR-039 §4).
// Run: node scripts/generate-pool-fit-fixtures.mjs
import { writeFileSync } from "node:fs";
import { Encoder, Profile } from "@garmin/fitsdk";

/**
 * A pool swim as a watch writes it: one `length` message per length (active or idle), one
 * `record` without position per length, then the session with the pool length.
 */
function poolSwim({ start, poolLengthM, unit, lengths }) {
  const at = (s) => new Date(start.getTime() + s * 1000);
  const enc = new Encoder();
  enc.onMesg(Profile.MesgNum.FILE_ID, {
    type: "activity",
    manufacturer: "development",
    product: 0,
    timeCreated: start,
    serialNumber: 1234,
  });
  let s = 0;
  lengths.forEach(([type, seconds], messageIndex) => {
    enc.onMesg(Profile.MesgNum.LENGTH, {
      messageIndex,
      timestamp: at(s + seconds),
      startTime: at(s),
      totalElapsedTime: seconds,
      totalTimerTime: seconds,
      lengthType: type,
      event: "length",
      eventType: "stop",
    });
    enc.onMesg(Profile.MesgNum.RECORD, { timestamp: at(s + seconds), heartRate: 140 });
    s += seconds;
  });
  const active = lengths.filter(([type]) => type === "active").length;
  enc.onMesg(Profile.MesgNum.SESSION, {
    timestamp: at(s),
    startTime: start,
    totalElapsedTime: s,
    totalTimerTime: s,
    sport: "swimming",
    subSport: "lapSwimming",
    poolLength: poolLengthM,
    poolLengthUnit: unit,
    numLengths: lengths.length,
    numActiveLengths: active,
    totalDistance: active * poolLengthM,
  });
  return enc.close();
}

// 25 m: 4 lengths (30, 28, 29, 31 s), 60 s of rest, 4 lengths (27, 27, 30, 30 s).
writeFileSync(
  new URL("../fixtures/pool-25m.fit", import.meta.url),
  poolSwim({
    start: new Date("2026-05-02T07:00:00Z"),
    poolLengthM: 25,
    unit: "metric",
    lengths: [
      ["active", 30],
      ["active", 28],
      ["active", 29],
      ["active", 31],
      ["idle", 60],
      ["active", 27],
      ["active", 27],
      ["active", 30],
      ["active", 30],
    ],
  }),
);

// 25 yd (22.86 m): 4 lengths of 25 s.
writeFileSync(
  new URL("../fixtures/pool-25yd.fit", import.meta.url),
  poolSwim({
    start: new Date("2026-05-03T07:00:00Z"),
    poolLengthM: 22.86,
    unit: "statute",
    lengths: [
      ["active", 25],
      ["active", 25],
      ["active", 25],
      ["active", 25],
    ],
  }),
);
