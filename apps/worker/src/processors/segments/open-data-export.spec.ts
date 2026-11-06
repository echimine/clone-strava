import { randomUUID } from "node:crypto";
import { gunzipSync } from "node:zlib";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  EXPORT_SEGMENTS_ODBL_JOB_NAME,
  OPEN_DATA_SEGMENTS_KEY,
  SEGMENTS_QUEUE_NAME,
  openDataSegmentFeatureSchema,
  openDataSegmentsHeaderSchema,
} from "@repo/contracts";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

/**
 * `export-segments-odbl` (ADR-039 §10, §13) on the real Postgres and Redis: every Segment, the
 * athletes' included, in the public ODbL file of the bucket; no creator, no Effort.
 */
describe("ODbL export of the Segments (integration)", () => {
  let ctx: TestWorkerApp;
  let queue: Queue;
  const users: string[] = [];
  const segments: string[] = [];

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    queue = ctx.app.get<Queue>(getQueueToken(SEGMENTS_QUEUE_NAME));
  }, 30_000);

  afterAll(async () => {
    await ctx.db.$client.query("delete from segments.segment where id = any($1::uuid[])", [segments]);
    await ctx.db.$client.query('delete from "user" where id = any($1::uuid[])', [users]);
    await ctx?.close();
  });

  async function newSegment(values: { name: string; sport: string; createdBy: string | null; origin: string }) {
    const id = randomUUID();
    segments.push(id);
    await ctx.db.$client.query(
      `insert into segments.segment (id, name, sport_type_code, created_by, origin, path, distance_m, elevation_gain_m,
         avg_grade, max_grade, climb_category)
       values ($1, $2, $3, $4, $5, ST_GeomFromEWKT('SRID=4326;LINESTRING Z(6 45 1000,6.01 45 1050,6.02 45 1100)'),
         1580, 100, 6.3, 8.1, '4')`,
      [id, values.name, values.sport, values.createdBy, values.origin],
    );
    return id;
  }

  it("writes every Segment to the bucket with the licence and its attributions", async () => {
    const athlete = randomUUID();
    users.push(athlete);
    await ctx.db.$client.query('insert into "user" (id, name, email) values ($1, $2, $3)', [athlete, "Créateur", `${athlete}@test.local`]);
    const mine = await newSegment({ name: "La bosse du quartier", sport: "run", createdBy: athlete, origin: "athlete" });
    const nervo = await newSegment({ name: "Col du Test depuis Valtest", sport: "ride", createdBy: null, origin: "nervo" });
    ctx.storage.objects.delete(OPEN_DATA_SEGMENTS_KEY);

    await queue.add(EXPORT_SEGMENTS_ODBL_JOB_NAME, {});

    const file = await waitFor(async () => ctx.storage.objects.get(OPEN_DATA_SEGMENTS_KEY));
    const text = gunzipSync(file).toString("utf8");
    const [first, ...rest] = text.trim().split("\n").map((line) => JSON.parse(line) as unknown);
    const header = openDataSegmentsHeaderSchema.parse(first);
    expect(header.license).toBe("ODbL-1.0");
    expect(header.attribution.join(" ")).toContain("OpenStreetMap");
    expect(header.attribution.join(" ")).toContain("Copernicus WorldDEM-30");
    const features = rest.map((line) => openDataSegmentFeatureSchema.parse(line));
    const byId = new Map(features.map((feature) => [feature.id, feature]));
    expect(byId.get(mine)).toEqual({
      type: "Feature",
      id: mine,
      geometry: { type: "LineString", coordinates: [[6, 45, 1000], [6.01, 45, 1050], [6.02, 45, 1100]] },
      properties: {
        name: "La bosse du quartier",
        sport: "run",
        distanceM: 1580,
        elevationGainM: 100,
        avgGrade: 6.3,
        maxGrade: 8.1,
        climbCategory: "4",
      },
    });
    expect(byId.get(nervo)?.properties.name).toBe("Col du Test depuis Valtest");
    // No creator, no provenance: the app never tells them apart.
    expect(text).not.toContain(athlete);
    expect(text).not.toContain("nervo");
  });
});
