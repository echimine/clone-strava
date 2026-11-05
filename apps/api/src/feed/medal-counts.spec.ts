import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ActivityDetail, FeedResponse } from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/**
 * `ActivityPost.medalCounts` (ADR-039 §12): « Performances » of the feed, the profile list and the
 * detail, over real HTTP and Postgres (ADR-024 §2). Best efforts not removed and Efforts added up,
 * never stored.
 */
describe("medalCounts on Activity cards (integration)", () => {
  let api: AthleteApp;
  let author: string;
  let stranger: string;
  const segments: string[] = [];

  async function bestEffort(activityId: string, distanceM: number, medal: string | null, removed = false) {
    await api.sql(
      `insert into activities.best_effort (activity_id, user_id, record_set, distance_m, elapsed_time_ms, start_distance_m,
         activity_started_at, medal, removed_at)
       select id, user_id, 'run', $2, 100000, 0, started_at, $3, $4 from activities.activity where id = $1`,
      [activityId, distanceM, medal, removed ? new Date() : null],
    );
  }

  async function segment(): Promise<string> {
    const id = randomUUID();
    segments.push(id);
    await api.sql(
      `insert into segments.segment (id, name, sport_type_code, path, start_point, end_point, distance_m)
       values ($1, 'Côte', 'run', ST_GeomFromEWKT('SRID=4326;LINESTRING Z(2.35 48.85 30, 2.36 48.85 32)'),
         ST_GeomFromEWKT('SRID=4326;POINT(2.35 48.85)'), ST_GeomFromEWKT('SRID=4326;POINT(2.36 48.85)'), 740)`,
      [id],
    );
    return id;
  }

  async function effort(
    activityId: string,
    segmentId: string,
    startIndex: number,
    medal: string,
    options: { status?: string; fromStartM?: number } = {},
  ) {
    await api.sql(
      `insert into segments.segment_effort (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index,
         end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m, status, medal)
       select id, $2, user_id, 180, started_at + make_interval(secs => $3), $3, $3 + 10, $4, 5000, $5, $6
       from activities.activity where id = $1`,
      [activityId, segmentId, startIndex, options.fromStartM ?? 5000, options.status ?? "valid", medal],
    );
  }

  const feedItem = async (activityId: string, viewer: string, path: string) => {
    const body = (await (await api.call(path, viewer)).json()) as FeedResponse;
    return body.items.find((item) => item.id === activityId);
  };
  const detail = async (activityId: string, viewer: string) =>
    (await (await api.call(`/activities/${activityId}`, viewer)).json()) as ActivityDetail;

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

  it("adds up the Medals of Best efforts not removed and Efforts not rejected, in the feed, the profile and the detail", async () => {
    const activity = await api.seedActivity(author);
    const climb = await segment();
    await bestEffort(activity, 400, "gold");
    await bestEffort(activity, 1000, "silver");
    await bestEffort(activity, 2000, "gold", true);
    await bestEffort(activity, 3000, null);
    await effort(activity, climb, 10, "gold");
    await effort(activity, climb, 50, "bronze");
    await effort(activity, climb, 90, "gold", { status: "rejected" });
    const expected = { gold: 2, silver: 1, bronze: 1 };

    expect((await feedItem(activity, author, "/feed"))?.medalCounts).toEqual(expected);
    expect((await feedItem(activity, stranger, `/athletes/${author}/activities`))?.medalCounts).toEqual(expected);
    expect((await detail(activity, stranger)).medalCounts).toEqual(expected);
  }, 30_000);

  it("counts nothing for an Activity without Medals", async () => {
    const activity = await api.seedActivity(author);

    expect((await detail(activity, author)).medalCounts).toEqual({ gold: 0, silver: 0, bronze: 0 });
  }, 30_000);

  it("leaves out the privacy zone's Efforts for everyone but the author, and a deleted Segment's at once", async () => {
    const activity = await api.seedActivity(author);
    const home = await segment();
    await effort(activity, home, 0, "gold", { fromStartM: 20 });

    expect((await detail(activity, author)).medalCounts.gold).toBe(1);
    expect((await detail(activity, stranger)).medalCounts.gold).toBe(0);

    await api.sql("delete from segments.segment where id = $1", [home]);
    expect((await detail(activity, author)).medalCounts.gold).toBe(0);
  }, 30_000);
});
