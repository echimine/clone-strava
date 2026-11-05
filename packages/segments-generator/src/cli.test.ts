import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { nervoSegmentLineSchema } from "@repo/contracts";
import { runCli } from "./cli.js";

const fixture = (name: string) => join(__dirname, "..", "fixtures", name);

function capture() {
  const lines: string[] = [];
  return { lines, write: (line: string) => lines.push(line) };
}

/**
 * The generator's command line on the versioned fixtures (`scripts/generate-fixtures.mjs`): an
 * `osmium export` extract and two EHdr rasters, nothing downloaded.
 */
describe("segments generator CLI (ADR-039 §10)", () => {
  it("writes one NDJSON line per Segment the import reads, and says what it made", async () => {
    const out = join(mkdtempSync(join(tmpdir(), "nervo-")), "pilote.ndjson");
    const log = capture();

    const code = await runCli(
      ["--osm", fixture("pilote.geojsonseq"), "--dem", fixture("mnt-national.hdr"), "--dem", fixture("mnt-secours.hdr"), "--out", out],
      log.write,
    );

    expect(code).toBe(0);
    const lines = readFileSync(out, "utf8").trim().split("\n").map((line) => nervoSegmentLineSchema.parse(JSON.parse(line)));
    expect(lines.map((line) => `${line.sport} ${line.name}`).sort()).toEqual([
      "hike Pic du Test depuis Hameau du Bas",
      // The east side lies in the national model's void: the fallback model measures it.
      "ride Col du Test depuis Autreville",
      "ride Col du Test depuis Valtest",
      "run Col du Test depuis Autreville",
      "run Col du Test depuis Valtest",
    ]);
    const fromEast = lines.find((line) => line.sport === "ride" && line.name.endsWith("Autreville"))!;
    expect(fromEast.distanceM).toBeGreaterThan(3800);
    const fromWest = lines.find((line) => line.sport === "ride" && line.name.endsWith("Valtest"))!;
    expect(fromWest.climbCategory).toBe("3");
    expect(fromWest.avgGrade).toBeGreaterThan(6.5);
    expect(fromWest.avgGrade).toBeLessThan(7.5);
    expect(log.lines.join("\n")).toMatch(/5 Segments \(ride 2, run 2, hike 1\)/);
  });

  it("documents the real inputs and their commands in --help", async () => {
    const log = capture();

    const code = await runCli(["--help"], log.write);

    expect(code).toBe(0);
    const help = log.lines.join("\n");
    expect(help).toContain("download.geofabrik.de/europe/france-latest.osm.pbf");
    expect(help).toContain("osmium export");
    expect(help).toContain("RGE ALTI");
    expect(help).toContain("copernicus-dem-30m");
    expect(help).toContain("gdalwarp");
    expect(help).toContain("pnpm segments:import");
  });

  it("refuses to run without its inputs", async () => {
    const log = capture();

    expect(await runCli(["--osm", fixture("pilote.geojsonseq")], log.write)).toBe(2);
    expect(log.lines.join("\n")).toContain("--dem");
  });
});
