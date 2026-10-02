// One-off generator for fixtures/ride.fit (ADR-028 §5). Run: node scripts/generate-fit-fixture.mjs
import { writeFileSync } from "node:fs";
import { Encoder, Profile } from "@garmin/fitsdk";

const start = new Date("2026-05-01T08:00:00Z");
const at = (s) => new Date(start.getTime() + s * 1000);
const SEMI = 2 ** 31 / 180;
const enc = new Encoder();

enc.onMesg(Profile.MesgNum.FILE_ID, {
  type: "activity",
  manufacturer: "development",
  product: 0,
  timeCreated: start,
  serialNumber: 1234,
});

for (let i = 0; i < 10; i++) {
  enc.onMesg(Profile.MesgNum.RECORD, {
    timestamp: at(i),
    positionLat: Math.round((48.85 + i * 0.0001) * SEMI),
    positionLong: Math.round((2.35 + i * 0.0001) * SEMI),
    enhancedAltitude: 35 + i,
    enhancedSpeed: 5 + i * 0.1,
    heartRate: 120 + i,
    cadence: 80,
  });
}
// A sample without position (indoor-like)
enc.onMesg(Profile.MesgNum.RECORD, { timestamp: at(10), heartRate: 130, cadence: 82 });

enc.onMesg(Profile.MesgNum.SESSION, {
  timestamp: at(10),
  startTime: start,
  totalElapsedTime: 10,
  totalTimerTime: 10,
  sport: "cycling",
  subSport: "mountain",
});

writeFileSync(new URL("../fixtures/ride.fit", import.meta.url), enc.close());
