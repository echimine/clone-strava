import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { SegmentSheet } from "@repo/contracts";
import { decodePolyline } from "@repo/geo";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";
import { segmentSeeds, type SegmentSeeds } from "../testing/segment-seeds.js";

/** `GET /v1/segments/:id` (ADR-039 §12, §15): the Segment sheet, free, over the real `AppModule`. */
describe("segment sheet (integration)", () => {
  let api: AthleteApp;
  let seeds: SegmentSeeds;

  const sheet = async (segmentId: string, as: string) => {
    const response = await api.call(`/segments/${segmentId}`, as);
    expect(response.status, await response.clone().text()).toBe(200);
    return (await response.json()) as SegmentSheet;
  };

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
    seeds = segmentSeeds(api);
  }, 60_000);

  afterAll(async () => {
    await seeds?.cleanup();
    await api?.close();
  });

  it("shows the Segment's figures, path and profile, favourites, and never its creator", async () => {
    const creator = await api.seedAthlete("Creator");
    const viewer = await api.seedAthlete("Vic");
    const segment = await seeds.segment({ name: "Col du test", createdBy: creator, verified: true, climbCategory: null });
    await seeds.favorite(segment, creator);
    await seeds.favorite(segment, viewer);

    const body = await sheet(segment, viewer);

    expect(body).toMatchObject({
      id: segment,
      name: "Col du test",
      sportTypeCode: "run",
      verified: true,
      distanceM: 1112,
      elevationGainM: 100,
      avgGrade: 9,
      climbCategory: null,
      starred: true,
      favoriteCount: 2,
      isMine: false,
      canDelete: false,
      historyMatching: false,
      myEfforts: [],
      myRecord: null,
      localLegend: { legend: null, myEffortCount: 0 },
      leaderboard: { limited: true, entries: [], me: null, athleteCount: 0 },
    });
    expect(decodePolyline(body.track.polyline6, 6)).toEqual([
      { lat: 44.6, lon: 3 },
      { lat: 44.605, lon: 3 },
      { lat: 44.61, lon: 3 },
    ]);
    expect(body.track.altitudesM).toEqual([500, 550, 600]);
    expect(JSON.stringify(body)).not.toContain(creator);
  });

  it("lets the creator delete it only while nobody else has an Effort, and shows the retro-matching", async () => {
    const creator = await api.seedAthlete("Creator");
    const other = await api.seedAthlete("Other");
    const segment = await seeds.segment({ createdBy: creator, historyMatched: false });
    await seeds.effort(segment, creator, { elapsedTimeS: 300 });

    expect(await sheet(segment, creator)).toMatchObject({ isMine: true, canDelete: true, historyMatching: true, starred: false });

    await seeds.effort(segment, other, { elapsedTimeS: 310, visibility: "private" });
    expect(await sheet(segment, creator)).toMatchObject({ isMine: true, canDelete: false });
  });

  it("lists every Effort of the viewer newest first, with Medals, the rank on their line only, and those that do not stand", async () => {
    const [fast, viewer] = await Promise.all(["Fast", "Vic"].map((n) => api.seedAthlete(n)));
    const segment = await seeds.segment();
    await seeds.effort(segment, fast!, { elapsedTimeS: 100 });
    const privateBest = await seeds.effort(segment, viewer!, {
      elapsedTimeS: 150,
      visibility: "private",
      startedAt: "2026-03-01T08:00:00Z",
      medal: "gold",
    });
    const line = await seeds.effort(segment, viewer!, { elapsedTimeS: 200, startedAt: "2026-02-01T08:00:00Z", medal: "silver" });
    const older = await seeds.effort(segment, viewer!, { elapsedTimeS: 250, startedAt: "2026-01-01T08:00:00Z", medal: "bronze" });
    await seeds.effort(segment, viewer!, { elapsedTimeS: 90, startedAt: "2025-12-01T08:00:00Z", status: "rejected" });

    const body = await sheet(segment, viewer!);

    expect(body.myEfforts.map((effort) => [effort.elapsedTimeS, effort.medal, effort.standing, effort.isLeaderboardLine, effort.rank])).toEqual([
      [150, "gold", false, false, null],
      [200, "silver", true, true, 2],
      [250, "bronze", true, false, null],
      [90, null, false, false, null],
    ]);
    expect(body.myEfforts[0]).toMatchObject({ id: privateBest.effortId, activityVisibility: "private" });
    expect(body.myEfforts[1]!.id).toBe(line.effortId);
    expect(body.myEfforts[2]!.id).toBe(older.effortId);
    expect(body.myRecord).toMatchObject({ id: privateBest.effortId, elapsedTimeS: 150 });
    expect(body.leaderboard.me).toMatchObject({ rank: 2, effortId: line.effortId });
    expect(body.leaderboard.entries.map((entry) => entry.athlete.id)).toEqual([fast, viewer]);
  });

  it("gives the Local Legend of Tous and the viewer's own 90-day count", async () => {
    const [legend, viewer] = await Promise.all(["Legend", "Vic"].map((n) => api.seedAthlete(n)));
    const segment = await seeds.segment();
    await seeds.effort(segment, legend!, { elapsedTimeS: 300 });
    await seeds.effort(segment, legend!, { elapsedTimeS: 300 });
    await seeds.effort(segment, viewer!, { elapsedTimeS: 300 });

    const body = await sheet(segment, viewer!);

    expect(body.localLegend).toEqual({
      legend: { athlete: { id: legend, displayName: "Legend Testeur", avatarUrl: null }, effortCount: 2 },
      myEffortCount: 1,
    });
  });

  it("answers 404 segment_not_found once deleted", async () => {
    const viewer = await api.seedAthlete("Vic");
    const segment = await seeds.segment();
    await api.sql("delete from segments.segment where id = $1", [segment]);

    const response = await api.call(`/segments/${segment}`, viewer);

    expect(response.status).toBe(404);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe("segment_not_found");
  });
});
