import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { activityImportSourceKey } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

/** The FIT fixtures of `@repo/track-files` (see its `scripts/generate-pool-fit-fixtures.mjs`). */
const fit = (name: string): Uint8Array =>
  new Uint8Array(readFileSync(join(__dirname, "../../../../../packages/track-files/fixtures", name)));

/**
 * A pool swim imported from FIT (ADR-039 §4), end to end on real Postgres and Redis: accepted
 * without positions, its distance from the lengths, no route, and its `swim_pool` Best efforts,
 * recomputed from the stored trace.
 */
describe("Pool swim import (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  const users: string[] = [];

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
  }, 30_000);

  afterAll(async () => {
    for (const userId of users) {
      await sql('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  async function sql<T = Record<string, unknown>>(text: string, params: unknown[]): Promise<T[]> {
    return (await ctx.db.$client.query(text, params)).rows as T[];
  }

  async function newAthlete(): Promise<string> {
    const userId = randomUUID();
    users.push(userId);
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [userId, "Swimmer", `${userId}@test.local`]);
    return userId;
  }

  /** Imports a FIT file and waits for its Activity to be processed; returns its id. */
  async function importedSwim(userId: string, file: Uint8Array): Promise<string> {
    const importId = randomUUID();
    await activities.createImport(userId, {
      id: importId,
      format: "fit",
      fileName: "swim.fit",
      sizeBytes: file.byteLength,
    });
    ctx.storage.objects.set(activityImportSourceKey(userId, importId, "fit"), file);
    await activities.completeImport(userId, importId, "req-test");
    const imported = await waitFor(async () => {
      const row = await activities.getImport(userId, importId);
      return row.status === "processing" || row.status === "pending" ? undefined : row;
    });
    expect(imported).toMatchObject({ status: "imported", activityId: importId });
    await waitFor(async () => {
      const [row] = await sql<{ processing_status: string }>(
        "select processing_status from activities.activity where id = $1",
        [importId],
      );
      return row?.processing_status === "processed" ? row : undefined;
    });
    return importId;
  }

  async function activityRow(id: string) {
    const [row] = await sql<{ sport_type_code: string; pool_length_m: number | null }>(
      "select sport_type_code, pool_length_m from activities.activity where id = $1",
      [id],
    );
    const [stats] = await sql<{ distance_m: number; moving_time_s: number; elapsed_time_s: number }>(
      "select distance_m, moving_time_s, elapsed_time_s from activities.activity_stats where activity_id = $1",
      [id],
    );
    const tracks = await sql("select 1 from activities.activity_track where activity_id = $1", [id]);
    return { ...row, stats, hasTrack: tracks.length > 0 };
  }

  async function bestEfforts(id: string) {
    const { bestEfforts } = await activities.getBestEffortResults(id);
    return bestEfforts.map((effort) => [effort.distanceM, effort.elapsedTimeMs, effort.medal]);
  }

  it("imports a 25 m pool swim without positions: distance from its lengths, no route, pool Records", async () => {
    const userId = await newAthlete();
    const id = await importedSwim(userId, fit("pool-25m.fit"));

    expect(await activityRow(id)).toEqual({
      sport_type_code: "swim",
      pool_length_m: 25,
      // 8 active lengths; 4:52 from the first length to the last, 3:52 of it swimming.
      stats: { distance_m: 200, moving_time_s: 232, elapsed_time_s: 292 },
      hasTrack: false,
    });
    // The minute of rest breaks the 200 m.
    expect(await bestEfforts(id)).toEqual([
      [50, 54_000, "gold"],
      [100, 114_000, "gold"],
    ]);
  }, 30_000);

  it("imports a pool in yards with its distance in meters, but no Record", async () => {
    const userId = await newAthlete();
    const id = await importedSwim(userId, fit("pool-25yd.fit"));

    const row = await activityRow(id);
    expect(row.sport_type_code).toBe("swim");
    expect(row.pool_length_m).toBeCloseTo(22.86, 4);
    expect(row.stats?.distance_m).toBeCloseTo(91.44, 2);
    expect(await bestEfforts(id)).toEqual([]);
  }, 30_000);

  it("recomputes the pool Records from the stored trace", async () => {
    const userId = await newAthlete();
    const id = await importedSwim(userId, fit("pool-25m.fit"));
    // As processed before ADR-039: an analysis v1, no Best effort.
    await sql("delete from activities.best_effort where activity_id = $1", [id]);
    await sql("update activities.activity_analysis set version = 1 where activity_id = $1", [id]);

    await activities.reprocess({ activityId: id, userId });

    expect(await bestEfforts(id)).toEqual([
      [50, 54_000, "gold"],
      [100, 114_000, "gold"],
    ]);
    expect((await activityRow(id)).hasTrack).toBe(false);
  }, 30_000);
});
