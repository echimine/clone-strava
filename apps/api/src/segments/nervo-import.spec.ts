import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  MATCH_SEGMENTS_JOB_NAME,
  SEGMENT_JOB_PRIORITY,
  SEGMENTS_QUEUE_NAME,
  matchSegmentsImportJobId,
  type NervoSegmentLine,
} from "@repo/contracts";
import { SegmentsService } from "@repo/core/segments";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;

/** A place of its own for each test, so the Segments of other tests are never duplicates. */
function newPlace() {
  const lat = 43 + Math.random() * 5;
  const lon = -1 + Math.random() * 7;
  const mPerDegLon = M_PER_DEG_LAT * Math.cos((lat * Math.PI) / 180);
  return (x: number, y = 0): [number, number] => [lon + x / mPerDegLon, lat + y / M_PER_DEG_LAT];
}

/** A generator line: 2 km east at 5 %, every 25 m. */
function nervoLine(at: ReturnType<typeof newPlace>, overrides: Partial<NervoSegmentLine> = {}): NervoSegmentLine {
  return {
    sourceKey: `osm:ride:${randomUUID()}`,
    sport: "ride",
    name: "Col du Test depuis Valtest",
    path: Array.from({ length: 81 }, (_, i) => [...at(i * 25), 1000 + i * 1.25] as [number, number, number]),
    distanceM: 2000,
    elevationGainM: 100,
    avgGrade: 5,
    maxGrade: 6.2,
    minAltitudeM: 1000,
    maxAltitudeM: 1100,
    climbCategory: "4",
    ...overrides,
  };
}

const ndjson = (...lines: NervoSegmentLine[]) => lines.map((line) => JSON.stringify(line));

/**
 * `pnpm segments:import` (ADR-039 §10): what `SegmentsService.importNervoSegments` does with the
 * generator's lines on the real Postgres and Redis, and the exclusion of a Nervo Segment an
 * Administrator deletes.
 */
describe("Nervo Segments import (integration)", () => {
  let ctx: AthleteApp;
  let segments: SegmentsService;
  let queue: Queue;
  const sourceKeys: string[] = [];
  const importIds: string[] = [];

  beforeAll(async () => {
    ctx = await bootstrapAthleteApp();
    segments = ctx.app.get(SegmentsService);
    queue = ctx.app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
  }, 30_000);

  afterAll(async () => {
    await ctx.sql("delete from segments.segment where source_key = any($1)", [sourceKeys]);
    await ctx.sql("delete from segments.excluded_source_key where source_key = any($1)", [sourceKeys]);
    const jobs = await queue.getJobs(["prioritized", "waiting", "delayed"]);
    await Promise.all(jobs.filter((job) => importIds.some((id) => job.id?.endsWith(id))).map((job) => job.remove()));
    await ctx.close();
  });

  async function importLines(lines: string[]) {
    const report = await segments.importNervoSegments(lines);
    importIds.push(report.importId);
    return report;
  }

  function tracked(line: NervoSegmentLine): NervoSegmentLine {
    sourceKeys.push(line.sourceKey);
    return line;
  }

  async function segmentBySourceKey(sourceKey: string) {
    const [row] = await ctx.sql<Record<string, unknown>>(
      `select id, name, sport_type_code, origin, created_by, verified_at, distance_m, avg_grade, max_grade,
              elevation_gain_m, min_altitude_m, max_altitude_m, climb_category, map_polyline,
              ST_NDims(path) as dims, ST_NPoints(path) as points, ST_Z(ST_StartPoint(path)) as start_z,
              ST_X(start_point) as start_lon, ST_X(end_point) as end_lon
         from segments.segment where source_key = $1`,
      [sourceKey],
    );
    return row;
  }

  it("inserts a Nervo Segment with no creator, unverified, with the generator's figures", async () => {
    const at = newPlace();
    const line = tracked(nervoLine(at));

    const report = await importLines(ndjson(line));

    expect(report).toMatchObject({ inserted: 1, alreadyPresent: 0, excluded: 0, duplicates: 0, invalid: [] });
    const row = await segmentBySourceKey(line.sourceKey);
    expect(row).toMatchObject({
      name: "Col du Test depuis Valtest",
      sport_type_code: "ride",
      origin: "nervo",
      created_by: null,
      verified_at: null,
      distance_m: 2000,
      avg_grade: 5,
      max_grade: 6.2,
      elevation_gain_m: 100,
      min_altitude_m: 1000,
      max_altitude_m: 1100,
      climb_category: "4",
      dims: 3,
      points: 81,
      start_z: 1000,
    });
    expect(row!.start_lon).toBeCloseTo(at(0)[0], 6);
    expect(row!.end_lon).toBeCloseTo(at(2000)[0], 6);
    expect(row!.map_polyline).toEqual(expect.any(String));
  });

  it("adds nothing on a rerun and never modifies a Segment, so a rename holds", async () => {
    const line = tracked(nervoLine(newPlace()));
    await importLines(ndjson(line));
    await ctx.sql("update segments.segment set name = 'Renommé par un Administrateur' where source_key = $1", [line.sourceKey]);

    const report = await importLines(ndjson(line));

    expect(report).toMatchObject({ inserted: 0, alreadyPresent: 1 });
    expect((await segmentBySourceKey(line.sourceKey))!.name).toBe("Renommé par un Administrateur");
  });

  it("never brings back a Nervo Segment an Administrator deleted", async () => {
    const line = tracked(nervoLine(newPlace()));
    await importLines(ndjson(line));
    const { id } = (await segmentBySourceKey(line.sourceKey)) as { id: string };

    expect(await segments.deleteSegmentAsAdministrator(id)).toEqual({ deleted: true, excludedSourceKey: line.sourceKey });
    const report = await importLines(ndjson(line));

    expect(report).toMatchObject({ inserted: 0, excluded: 1 });
    expect(await segmentBySourceKey(line.sourceKey)).toBeUndefined();
  });

  it("deletes an athlete's Segment without excluding anything", async () => {
    const athlete = await ctx.seedAthlete("Créatrice");
    const at = newPlace();
    const [{ id }] = (await ctx.sql<{ id: string }>(
      `insert into segments.segment (name, sport_type_code, created_by, path)
       values ('À moi', 'run', $1, ST_GeomFromEWKT($2)) returning id`,
      [athlete, `SRID=4326;LINESTRING Z(${at(0).join(" ")} 10,${at(500).join(" ")} 20)`],
    )) as [{ id: string }];

    expect(await segments.deleteSegmentAsAdministrator(id)).toEqual({ deleted: true, excludedSourceKey: null });
    expect(await segments.deleteSegmentAsAdministrator(id)).toEqual({ deleted: false, excludedSourceKey: null });
  });

  it("skips a duplicate of an existing Segment of the same sport: the athlete's stays", async () => {
    const athlete = await ctx.seedAthlete("Grimpeuse");
    const at = newPlace();
    const line = tracked(nervoLine(at));
    const wkt = line.path.map(([lon, lat, z]) => `${lon} ${lat} ${z}`).join(",");
    await ctx.sql(
      `insert into segments.segment (name, sport_type_code, created_by, path, start_point, end_point, distance_m)
       values ('Ma montée', 'ride', $1, ST_GeomFromEWKT($2), ST_SetSRID(ST_MakePoint($3, $4), 4326),
               ST_SetSRID(ST_MakePoint($5, $6), 4326), 2000)`,
      [athlete, `SRID=4326;LINESTRING Z(${wkt})`, ...at(0), ...at(2000)],
    );
    const forRunners = tracked(nervoLine(at, { sport: "run" }));

    const report = await importLines(ndjson(line, forRunners));

    expect(report).toMatchObject({ inserted: 1, duplicates: 1 });
    expect(await segmentBySourceKey(line.sourceKey)).toBeUndefined();
    expect(await segmentBySourceKey(forRunners.sourceKey)).toBeDefined();
  });

  it("skips a line twice in the same file, and an invalid line, without stopping", async () => {
    const at = newPlace();
    const line = tracked(nervoLine(at));
    const sameClimbOtherKey = tracked(nervoLine(at));

    const report = await importLines([...ndjson(line, sameClimbOtherKey), "{not json", JSON.stringify({ ...line, sport: "walk" })]);

    expect(report).toMatchObject({ inserted: 1, duplicates: 1 });
    expect(report.invalid.map((entry) => entry.line)).toEqual([3, 4]);
  });

  it("then replays match-segments at low priority for every processed Activity of the map sports", async () => {
    const athlete = await ctx.seedAthlete("Rouleuse");
    const run = await ctx.seedActivity(athlete);
    const [{ id: swim }] = (await ctx.sql<{ id: string }>(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
       values (gen_random_uuid(), $1, 'swim', 'Piscine', now() - interval '2 hours', now() - interval '1 hour', 'public', 'processed') returning id`,
      [athlete],
    )) as [{ id: string }];

    const report = await importLines(ndjson(tracked(nervoLine(newPlace()))));

    expect(report.activitiesEnqueued).toBeGreaterThanOrEqual(1);
    const job = await queue.getJob(matchSegmentsImportJobId(run, report.importId));
    expect(job).toMatchObject({ name: MATCH_SEGMENTS_JOB_NAME, data: { activityId: run, userId: athlete } });
    expect(job!.opts.priority).toBe(SEGMENT_JOB_PRIORITY.backgroundMatching);
    expect(await queue.getJob(matchSegmentsImportJobId(swim, report.importId))).toBeUndefined();
  });

  it("enqueues nothing when nothing was added", async () => {
    const line = tracked(nervoLine(newPlace()));
    await importLines(ndjson(line));

    const report = await importLines(ndjson(line));

    expect(report.activitiesEnqueued).toBe(0);
  });
});
