import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { activityImportSourceKey, activityTraceKey } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

/** 10 minutes of running, one point per minute, ~111 m apart, starting at `start`. */
function runGpx(start: Date): Uint8Array {
  const trkpts = Array.from({ length: 11 }, (_, i) => {
    const time = new Date(start.getTime() + i * 60_000).toISOString();
    return `<trkpt lat="${48.85 + i * 0.001}" lon="2.35"><ele>${35 + i}</ele><time>${time}</time></trkpt>`;
  }).join("");
  return new TextEncoder().encode(
    `<?xml version="1.0" encoding="UTF-8"?><gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">` +
      `<trk><type>running</type><trkseg>${trkpts}</trkseg></trk></gpx>`,
  );
}

/**
 * End-to-end `import-activity` -> `process-activity` on real Postgres and
 * Redis (ADR-024 §4): `complete` enqueues, the worker imports, chains the
 * processing, and the realtime bridge publishes on Redis.
 */
describe("import-activity (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  let userId: string;

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
    userId = randomUUID();
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Import test",
      `${userId}@test.local`,
    ]);
  }, 30_000);

  afterAll(async () => {
    if (userId) {
      // Cascades to the user's imports and activities.
      await sql('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  /** Raw SQL: this app has no direct `drizzle-orm` dependency (and pnpm resolves two copies). */
  async function sql<T = Record<string, unknown>>(text: string, params: unknown[]): Promise<T[]> {
    return (await ctx.db.$client.query(text, params)).rows as T[];
  }

  async function startImport(file: Uint8Array): Promise<string> {
    const importId = randomUUID();
    await activities.createImport(userId, {
      id: importId,
      format: "gpx",
      fileName: "run.gpx",
      sizeBytes: file.byteLength,
    });
    ctx.storage.objects.set(activityImportSourceKey(userId, importId, "gpx"), file);
    await activities.completeImport(userId, importId, "req-test");
    return importId;
  }

  it("imports a GPX file, then processes the new activity", async () => {
    const file = runGpx(new Date("2026-05-01T06:00:00Z"));
    const importId = await startImport(file);

    const imported = await waitFor(async () => {
      const row = await activities.getImport(userId, importId);
      return row.status === "processing" || row.status === "pending" ? undefined : row;
    });
    expect(imported).toMatchObject({ status: "imported", activityId: importId });

    const activity = await waitFor(async () => {
      const [row] = await sql(
        "select user_id, sport_type_code, source, title, processing_status from activities.activity where id = $1",
        [importId],
      );
      return row?.processing_status === "processed" ? row : undefined;
    });
    expect(activity).toMatchObject({
      user_id: userId,
      sport_type_code: "run",
      source: "imported",
      title: "Course à pied le matin",
    });

    const [stats] = await sql<{ distance_m: number; elapsed_time_s: number }>(
      "select distance_m, elapsed_time_s from activities.activity_stats where activity_id = $1",
      [importId],
    );
    expect(stats?.distance_m).toBeGreaterThan(1000);
    expect(stats?.elapsed_time_s).toBe(600);

    const [track] = await sql<{ route: string | null; map_polyline: string | null; location_name: string | null }>(
      "select ST_AsText(route) as route, map_polyline, location_name from activities.activity_track where activity_id = $1",
      [importId],
    );
    expect(track?.route).toMatch(/^LINESTRING/);
    // ADR-029: feed map data; no geocoding token in tests, so no place name.
    expect(track?.map_polyline?.length).toBeGreaterThan(0);
    expect(track?.location_name).toBeNull();

    const types = await waitFor(async () => {
      const mine = ctx.realtimeMessages
        .filter((message) => message.topics.includes(`user:${userId}`))
        .map((message) => message.envelope.t);
      return mine.includes("activity.processed") ? mine : undefined;
    });
    expect(types).toContain("activity_import.completed");
  }, 30_000);

  it("marks a second upload of the same file as duplicate", async () => {
    const file = runGpx(new Date("2026-05-01T06:00:00Z"));
    const importId = await startImport(file);

    const result = await waitFor(async () => {
      const row = await activities.getImport(userId, importId);
      return row.status === "processing" ? undefined : row;
    });
    expect(result.status).toBe("duplicate");
    expect(result.activityId).not.toBe(importId);
  }, 30_000);

  it("deletes an imported activity with its files, keeps the import, and lets the same file be imported again", async () => {
    const file = runGpx(new Date("2026-06-01T06:00:00Z"));
    const importId = await startImport(file);
    await waitFor(async () => {
      const [row] = await sql("select processing_status from activities.activity where id = $1", [importId]);
      return row?.processing_status === "processed" ? row : undefined;
    });
    const sourceKey = activityImportSourceKey(userId, importId, "gpx");
    expect(ctx.storage.objects.has(sourceKey)).toBe(true);
    expect(ctx.storage.objects.has(activityTraceKey(userId, importId))).toBe(true);

    await activities.delete(userId, importId);

    expect(ctx.storage.objects.has(sourceKey)).toBe(false);
    expect(ctx.storage.objects.has(activityTraceKey(userId, importId))).toBe(false);
    const [kept] = await sql<{ status: string; activity_id: string | null }>(
      "select status, activity_id from activities.activity_import where id = $1",
      [importId],
    );
    expect(kept).toEqual({ status: "imported", activity_id: null });
    await waitFor(async () =>
      ctx.realtimeMessages.find(
        (message) =>
          message.topics.includes(`user:${userId}`) &&
          message.envelope.t === "activity.deleted" &&
          message.envelope.data.activityId === importId,
      ),
    );

    const againId = await startImport(file);
    const again = await waitFor(async () => {
      const row = await activities.getImport(userId, againId);
      return row.status === "processing" ? undefined : row;
    });
    expect(again).toMatchObject({ status: "imported", activityId: againId });
  }, 30_000);

  it("fails an unreadable file without retrying it", async () => {
    const importId = await startImport(new TextEncoder().encode("<gpx><trk><trkseg>"));

    const result = await waitFor(async () => {
      const row = await activities.getImport(userId, importId);
      return row.status === "processing" ? undefined : row;
    });
    expect(result).toMatchObject({ status: "failed", error: "invalid_file" });

    const [row] = await sql<{ attempts: number }>(
      "select attempts from activities.activity_import where id = $1",
      [importId],
    );
    expect(row?.attempts).toBe(1);
  }, 30_000);
});
