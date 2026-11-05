import { describe, expect, it } from "vitest";
import { generateSegments } from "./generate.js";
import { ramp, world } from "./testing/world.js";

/** A pass at x = 4,000 m: 4 km at 7 % from the west, 4 km at 7 % from the east. */
function colAt4000(x: number): number {
  return x <= 4000 ? ramp(0, 4000, 7)(x) : ramp(0, 4000, 7)(8000 - x);
}

const xOf = (w: ReturnType<typeof world>, [lon, lat]: number[]) => w.toXy(lon!, lat!).x;

describe("generateSegments (ADR-039 §10)", () => {
  it("makes a ride Segment of a road climb to a named pass, named after it and the place below", () => {
    const w = world();
    w.way({ highway: "secondary", ref: "D 900" }, [-500, 0], [8500, 0]);
    w.node({ mountain_pass: "yes", name: "Col du Test" }, 4000, 0);
    w.node({ place: "village", name: "Valtest" }, -300, 200);

    const segments = generateSegments(w.osm(), w.elevation((x) => colAt4000(x)));

    const fromWest = segments.find((s) => s.sport === "ride" && s.name === "Col du Test depuis Valtest");
    expect(fromWest).toBeDefined();
    expect(fromWest!.distanceM).toBeGreaterThan(3900);
    expect(fromWest!.distanceM).toBeLessThan(4100);
    expect(fromWest!.avgGrade).toBeCloseTo(7, 0);
    expect(fromWest!.elevationGainM).toBeGreaterThan(270);
    expect(fromWest!.elevationGainM).toBeLessThan(290);
    expect(fromWest!.minAltitudeM).toBeCloseTo(1000, -1);
    expect(fromWest!.maxAltitudeM).toBeCloseTo(1280, -1);
    // 4,000 m × 7 % = 28,000: a Cat. 3.
    expect(fromWest!.climbCategory).toBe("3");
    // From the foot to the pass, within the ±50 m of the smoothing.
    expect(Math.abs(xOf(w, fromWest!.path[0]!) - 0)).toBeLessThan(75);
    expect(Math.abs(xOf(w, fromWest!.path.at(-1)!) - 4000)).toBeLessThan(75);
    expect(fromWest!.path[0]![2]).toBeCloseTo(1000, -1);
  });

  it("makes one Segment per side of the pass, from the way split in several", () => {
    const w = world();
    w.way({ highway: "secondary", ref: "D 900" }, [-500, 0], [2000, 0]);
    w.way({ highway: "secondary", ref: "D 900" }, [6000, 0], [2000, 0]);
    w.way({ highway: "secondary", ref: "D 900" }, [6000, 0], [8500, 0]);
    w.node({ mountain_pass: "yes", name: "Col du Test", "name:fr": "Col du Test" }, 4000, 0);
    w.node({ place: "village", name: "Valtest" }, -300, 200);
    w.node({ place: "village", name: "Autreville" }, 8300, -200);

    const ride = generateSegments(w.osm(), w.elevation((x) => colAt4000(x))).filter((s) => s.sport === "ride");

    expect(ride.map((s) => s.name).sort()).toEqual(["Col du Test depuis Autreville", "Col du Test depuis Valtest"]);
    expect(new Set(ride.map((s) => s.sourceKey)).size).toBe(2);
  });

  it("names a climb without a pass after its road and the place at the top", () => {
    const w = world();
    w.way({ highway: "tertiary", name: "Route de Hautville" }, [-500, 0], [3500, 0]);
    w.node({ place: "village", name: "Hautville" }, 3300, 200);

    const [segment] = generateSegments(w.osm(), w.elevation(ramp(0, 3000, 6))).filter((s) => s.sport === "ride");

    expect(segment?.name).toBe("Montée de la route de Hautville à Hautville");
    // 3,000 m × 6 % = 18,000.
    expect(segment?.climbCategory).toBe("3");
  });

  it("names a numbered road « Montée de la D 902 »", () => {
    const w = world();
    w.way({ highway: "primary", ref: "D 902" }, [-500, 0], [3500, 0]);
    w.node({ place: "village", name: "Saint-Véran" }, 3200, 0);

    const names = generateSegments(w.osm(), w.elevation(ramp(0, 3000, 6))).map((s) => s.name);

    expect(names).toContain("Montée de la D 902 à Saint-Véran");
  });

  it("makes no Segment without a usable name", () => {
    const w = world();
    // No name, no ref, no pass: nothing to call it.
    w.way({ highway: "tertiary" }, [-500, 0], [3500, 0]);
    w.node({ place: "village", name: "Hautville" }, 3300, 200);
    // A name but no place within reach of the top.
    w.way({ highway: "tertiary", name: "Route perdue" }, [-500, 30_000], [3500, 30_000]);

    expect(generateSegments(w.osm(), w.elevation(ramp(0, 3000, 6)))).toEqual([]);
  });

  it("keeps only Cat. 4 climbs and up by bike, at least 500 m and 3 %", () => {
    const w = world();
    w.node({ place: "town", name: "Plaineville" }, 0, 5_000);
    // 1,500 m at 5 % = 7,500: under the 8,000.
    w.way({ highway: "tertiary", name: "Côte douce" }, [-500, 0], [2000, 0]);
    // 350 m at 30 % (10,500): too short, and too steep for a road (a model artefact).
    w.way({ highway: "tertiary", name: "Mur court" }, [-500, 2000], [600, 2000]);
    // 10 km at 2 %: too gentle.
    w.way({ highway: "tertiary", name: "Faux plat" }, [-500, 4000], [10_500, 4000]);
    // Flat.
    w.way({ highway: "tertiary", name: "Route plate" }, [-500, 6000], [5000, 6000]);
    const altitude = (x: number, y: number) =>
      y < 1000 ? ramp(0, 1500, 5)(x) : y < 3000 ? ramp(0, 350, 30)(x) : y < 5000 ? ramp(0, 10_000, 2)(x) : 1000;

    expect(generateSegments(w.osm(), w.elevation(altitude)).filter((s) => s.sport === "ride")).toEqual([]);
  });

  it("follows a one-way road only its way", () => {
    const w = world();
    w.way({ highway: "secondary", ref: "D 900", oneway: "yes" }, [8500, 0], [-500, 0]);
    w.node({ mountain_pass: "yes", name: "Col du Test" }, 4000, 0);
    w.node({ place: "village", name: "Valtest" }, -300, 200);
    w.node({ place: "village", name: "Autreville" }, 8300, -200);

    const ride = generateSegments(w.osm(), w.elevation((x) => colAt4000(x))).filter((s) => s.sport === "ride");

    expect(ride.map((s) => s.name)).toEqual(["Col du Test depuis Autreville"]);
  });

  it("keeps one Segment when two ways run along the same climb", () => {
    const w = world();
    w.way({ highway: "secondary", ref: "D 900" }, [-500, 0], [4500, 0]);
    w.way({ highway: "cycleway", name: "Voie verte du col" }, [-500, 3], [4500, 3]);
    w.node({ mountain_pass: "yes", name: "Col du Test" }, 4000, 0);
    w.node({ place: "village", name: "Valtest" }, -300, 200);

    const ride = generateSegments(w.osm(), w.elevation((x) => colAt4000(x))).filter((s) => s.sport === "ride");

    expect(ride).toHaveLength(1);
  });

  it("gives the same source keys on the same data", () => {
    const build = () => {
      const w = world();
      w.way({ highway: "secondary", ref: "D 900" }, [-500, 0], [8500, 0]);
      w.node({ mountain_pass: "yes", name: "Col du Test" }, 4000, 0);
      w.node({ place: "village", name: "Valtest" }, -300, 200);
      return generateSegments(w.osm(), w.elevation((x) => colAt4000(x))).map((s) => s.sourceKey);
    };

    expect(build()).toEqual(build());
    expect(build().every((key) => key.startsWith("osm:"))).toBe(true);
  });

  describe("on foot", () => {
    it("makes a run Segment of a road climb runnable on foot, none where feet are banned", () => {
      const w = world();
      w.way({ highway: "secondary", ref: "D 900" }, [-500, 0], [4500, 0]);
      w.way({ highway: "secondary", ref: "D 901", foot: "no" }, [-500, 10_000], [4500, 10_000]);
      w.node({ mountain_pass: "yes", name: "Col du Test" }, 4000, 0);
      w.node({ mountain_pass: "yes", name: "Col interdit" }, 4000, 10_000);
      w.node({ place: "village", name: "Valtest" }, -300, 200);
      w.node({ place: "village", name: "Interville" }, -300, 10_200);

      const segments = generateSegments(w.osm(), w.elevation((x) => colAt4000(x)));

      expect(segments.filter((s) => s.sport === "run").map((s) => s.name)).toEqual(["Col du Test depuis Valtest"]);
      expect(segments.filter((s) => s.sport === "ride").map((s) => s.name).sort()).toEqual([
        "Col du Test depuis Valtest",
        "Col interdit depuis Interville",
      ]);
    });

    it("makes a run Segment of a short urban climb, a few per town", () => {
      const w = world();
      w.node({ place: "town", name: "Valtest-le-Haut" }, 200, 800);
      // Five streets climbing 400 m at 6 % (2,400), one at 5 % (2,000), one at 2 %.
      const grades = [6, 6, 6, 6, 5, 2];
      grades.forEach((_, i) => w.way({ highway: "residential", name: `Rue ${i + 1}` }, [-100, i * 300], [500, i * 300]));
      const altitude = (x: number, y: number) => ramp(0, 400, grades[Math.round(y / 300)] ?? 0)(x);

      const segments = generateSegments(w.osm(), w.elevation(altitude));

      const run = segments.filter((s) => s.sport === "run");
      expect(run).toHaveLength(3);
      expect(run.every((s) => s.name.startsWith("Montée de la rue ") && s.name.endsWith(" à Valtest-le-Haut"))).toBe(true);
      expect(run.every((s) => s.climbCategory === null)).toBe(true);
      // Too small for a bike, and never anything for a walk.
      expect(segments.filter((s) => s.sport !== "run")).toEqual([]);
    });

    it("makes a hike Segment of a path to a named summit, up to demanding mountain hiking", () => {
      const w = world();
      w.way({ highway: "path", sac_scale: "mountain_hiking" }, [-200, 0], [2000, 0]);
      w.way({ highway: "path", sac_scale: "alpine_hiking" }, [-200, 3000], [2000, 3000]);
      w.way({ highway: "path" }, [-200, 6000], [2000, 6000]);
      w.node({ natural: "peak", name: "Pic du Test" }, 2000, 0);
      w.node({ natural: "peak", name: "Aiguille du Test" }, 2000, 3000);
      // No name: no summit to go to.
      w.node({ natural: "peak" }, 2000, 6000);
      w.node({ place: "hamlet", name: "Hameau du Bas" }, -300, 100);

      const segments = generateSegments(w.osm(), w.elevation(ramp(0, 2000, 15, 1200)));

      expect(segments.map((s) => [s.sport, s.name])).toEqual([["hike", "Pic du Test depuis Hameau du Bas"]]);
      // 2,000 m × 15 % = 30,000.
      expect(segments[0]!.climbCategory).toBe("3");
    });
  });
});
