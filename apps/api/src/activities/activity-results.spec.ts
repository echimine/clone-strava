import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ActivityResults } from "@repo/contracts";
import { SEGMENT_MATCHING_VERSION } from "@repo/core/segments";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/**
 * `GET /v1/activities/:id/results` (ADR-039 §12) over real HTTP and Postgres (ADR-024 §2): Best
 * efforts from `activities`, Efforts from `segments`, composed by `apps/api`.
 */
describe("GET /v1/activities/:id/results (integration)", () => {
  let api: AthleteApp;
  let author: string;
  let stranger: string;
  const segments: string[] = [];

  const results = async (activityId: string, viewer: string) => {
    const response = await api.call(`/activities/${activityId}/results`, viewer);
    return { status: response.status, body: (await response.json()) as ActivityResults };
  };

  async function startedAt(activityId: string): Promise<Date> {
    const [row] = await api.sql<{ started_at: Date }>("select started_at from activities.activity where id = $1", [
      activityId,
    ]);
    return row!.started_at;
  }

  async function bestEffort(
    activityId: string,
    distanceM: number,
    elapsedTimeMs: number,
    options: { medal?: string | null; removed?: boolean } = {},
  ) {
    await api.sql(
      `insert into activities.best_effort (activity_id, user_id, record_set, distance_m, elapsed_time_ms, start_distance_m,
         activity_started_at, medal, removed_at)
       select id, user_id, 'run', $2, $3, 0, started_at, $4, $5 from activities.activity where id = $1`,
      [activityId, distanceM, elapsedTimeMs, options.medal ?? null, options.removed ? new Date() : null],
    );
  }

  /** A Segment of 740 m starting at (48.85, 2.35). */
  async function segment(name: string, options: { verified?: boolean } = {}): Promise<string> {
    const id = randomUUID();
    segments.push(id);
    await api.sql(
      `insert into segments.segment (id, name, sport_type_code, path, start_point, end_point, distance_m, verified_at)
       values ($1, $2, 'run', ST_GeomFromEWKT('SRID=4326;LINESTRING Z(2.35 48.85 30, 2.36 48.85 32)'),
         ST_GeomFromEWKT('SRID=4326;POINT(2.35 48.85)'), ST_GeomFromEWKT('SRID=4326;POINT(2.36 48.85)'), 740, $3)`,
      [id, name, options.verified ? new Date() : null],
    );
    return id;
  }

  async function effort(
    activityId: string,
    segmentId: string,
    options: {
      startIndex: number;
      elapsedTimeS?: number;
      medal?: string | null;
      status?: string;
      startedAt?: Date;
      fromStartM?: number;
    },
  ) {
    const started = options.startedAt ?? new Date((await startedAt(activityId)).getTime() + options.startIndex * 1000);
    await api.sql(
      `insert into segments.segment_effort (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index,
         end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m, status, medal)
       select id, $2, user_id, $3, $4, $5, $5 + 10, $6, 5000, $7, $8 from activities.activity where id = $1`,
      [activityId, segmentId, options.elapsedTimeS ?? 180, started, options.startIndex, options.fromStartM ?? 5000,
        options.status ?? "valid", options.medal ?? null],
    );
  }

  async function matched(activityId: string, version = SEGMENT_MATCHING_VERSION) {
    await api.sql("insert into segments.activity_matching (activity_id, version) values ($1, $2)", [
      activityId,
      version,
    ]);
  }

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
    author = await api.seedAthlete("Léa");
    stranger = await api.seedAthlete("Tom");
  }, 30_000);

  afterAll(async () => {
    if (segments.length > 0) {
      await api.sql("delete from segments.segment where id = any($1)", [segments]);
    }
    await api.close();
  });

  it("lists the Best efforts not removed, with Medal, first time, current Record and removable for the author", async () => {
    const earlier = await api.seedActivity(author);
    const activity = await api.seedActivity(author);
    await api.sql("update activities.activity set started_at = started_at - interval '10 days' where id = $1", [earlier]);
    await bestEffort(earlier, 1000, 250_000, { medal: "gold" });
    await bestEffort(activity, 400, 90_000, { medal: "gold" });
    await bestEffort(activity, 1000, 260_000, { medal: "silver" });
    await bestEffort(activity, 2000, 600_000, { removed: true });
    await matched(activity);

    const own = await results(activity, author);

    expect(own.status).toBe(200);
    expect(own.body.bestEfforts).toEqual([
      { distanceM: 400, elapsedTimeMs: 90_000, medal: "gold", isFirst: true, isCurrentRecord: true, removable: true },
      { distanceM: 1000, elapsedTimeMs: 260_000, medal: "silver", isFirst: false, isCurrentRecord: false, removable: true },
    ]);
    const seen = await results(activity, stranger);
    expect(seen.body.bestEfforts.map((effort) => effort.removable)).toEqual([false, false]);
  }, 30_000);

  it("lists the Efforts in trace order with their Segment, Medal, first pass and start, rejected ones left out", async () => {
    const earlier = await api.seedActivity(author);
    const activity = await api.seedActivity(author);
    const lake = await segment("Tour du lac", { verified: true });
    const climb = await segment("Montée du col");
    await effort(earlier, lake, { startIndex: 0, startedAt: new Date(Date.now() - 30 * 86_400_000), medal: "gold" });
    await effort(activity, climb, { startIndex: 40, elapsedTimeS: 300, medal: "gold" });
    await effort(activity, lake, { startIndex: 10, elapsedTimeS: 170, medal: "gold" });
    await effort(activity, climb, { startIndex: 90, status: "rejected" });
    await matched(activity);

    const { body } = await results(activity, stranger);

    expect(body.matchingInProgress).toBe(false);
    expect(body.efforts).toEqual([
      {
        id: expect.any(String),
        segment: { id: lake, name: "Tour du lac", distanceM: 740, verified: true },
        elapsedTimeS: 170,
        medal: "gold",
        isFirstPass: false,
        localLegend: false,
        startPoint: { lat: 48.85, lon: 2.35 },
      },
      {
        id: expect.any(String),
        segment: { id: climb, name: "Montée du col", distanceM: 740, verified: false },
        elapsedTimeS: 300,
        medal: "gold",
        isFirstPass: true,
        localLegend: false,
        startPoint: { lat: 48.85, lon: 2.35 },
      },
    ]);
  }, 30_000);

  it("leaves out the Efforts in the privacy zone for everyone but the author", async () => {
    const activity = await api.seedActivity(author);
    const lake = await segment("Départ de la maison");
    await effort(activity, lake, { startIndex: 0, fromStartM: 50, medal: "gold" });
    await matched(activity);

    expect((await results(activity, author)).body.efforts).toHaveLength(1);
    expect((await results(activity, stranger)).body.efforts).toEqual([]);
  }, 30_000);

  it("says the matching is in progress without a matching row or with an older version", async () => {
    const never = await api.seedActivity(author);
    const lagging = await api.seedActivity(author);
    await matched(lagging, SEGMENT_MATCHING_VERSION - 1);

    expect((await results(never, author)).body.matchingInProgress).toBe(true);
    expect((await results(lagging, author)).body.matchingInProgress).toBe(true);
  }, 30_000);

  it("gives the pool length of a pool swim", async () => {
    const activity = await api.seedActivity(author);
    await api.sql("update activities.activity set sport_type_code = 'swim', pool_length_m = 25 where id = $1", [activity]);
    await matched(activity);

    const { body } = await results(activity, author);

    expect(body.poolLengthM).toBe(25);
    expect(body.efforts).toEqual([]);
  }, 30_000);

  it("answers 404 when the viewer may not see the Activity", async () => {
    const hidden = await api.seedActivity(author, { visibility: "private" });

    expect((await results(hidden, stranger)).status).toBe(404);
    expect((await results(randomUUID(), stranger)).status).toBe(404);
  }, 30_000);
});
