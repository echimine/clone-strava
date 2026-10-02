/**
 * Raw sport strings found in files (ADR-028 §5 "Metadata"), lowercased by
 * `@repo/track-files`: FIT `sport[:sub_sport]`, TCX `Sport`, GPX
 * `trk/type`. Mapped to `sport_type.code`; unknown values give `undefined`
 * and never fail the import on their own.
 */
const SPORT_ALIASES: Record<string, string> = {
  running: "run",
  run: "run",
  trail_running: "run",
  "trail running": "run",
  treadmill: "run",
  cycling: "ride",
  biking: "ride",
  bike: "ride",
  ride: "ride",
  road_biking: "ride",
  mountain_biking: "ride",
  "mountain biking": "ride",
  e_biking: "ride",
  swimming: "swim",
  swim: "swim",
  open_water_swimming: "swim",
  walking: "walk",
  walk: "walk",
  hiking: "hike",
  hike: "hike",
};

export function mapFileSportToCode(rawSport: string | undefined): string | undefined {
  if (!rawSport) {
    return undefined;
  }
  const normalized = rawSport.trim().toLowerCase();
  // FIT gives `sport:sub_sport`, e.g. `cycling:mountain`: the main sport decides.
  const [main = ""] = normalized.split(":");
  return SPORT_ALIASES[normalized] ?? SPORT_ALIASES[main] ?? SPORT_ALIASES[main.replace(/\s+/g, "_")];
}
