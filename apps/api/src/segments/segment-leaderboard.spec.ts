import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { LeaderboardResponse } from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";
import { segmentSeeds, type SegmentSeeds } from "../testing/segment-seeds.js";

/**
 * `GET /v1/segments/:id/leaderboard` (ADR-039 §8, §9) over the real `AppModule`: one line per
 * athlete, the Efforts that stand, ties to the second, the viewer filter, the filters, the Local
 * Legend and Premium gated by the server.
 */
describe("segment leaderboard (integration)", () => {
  let api: AthleteApp;
  let seeds: SegmentSeeds;

  const leaderboard = async (segmentId: string, as: string, query = "") => {
    const response = await api.call(`/segments/${segmentId}/leaderboard${query}`, as);
    expect(response.status, await response.clone().text()).toBe(200);
    return (await response.json()) as LeaderboardResponse;
  };
  const errorOf = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;

  const ranks = (body: LeaderboardResponse) =>
    body.entries.map((entry) => [entry.rank, entry.athlete.id, entry.elapsedTimeS]);

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
    seeds = segmentSeeds(api);
  }, 60_000);

  afterAll(async () => {
    await api?.close();
  });

  it("keeps one line per athlete, their best Effort, ties to the second sharing the rank, older first", async () => {
    const segment = await seeds.segment();
    const [ann, bob, cid, viewer] = await Promise.all(["Ann", "Bob", "Cid", "Vic"].map((name) => api.seedAthlete(name)));
    await seeds.effort(segment, ann!, { elapsedTimeS: 300, startedAt: "2026-01-02T10:00:00Z" });
    await seeds.effort(segment, ann!, { elapsedTimeS: 280, startedAt: "2026-02-02T10:00:00Z" });
    await seeds.effort(segment, bob!, { elapsedTimeS: 280, startedAt: "2026-01-15T10:00:00Z" });
    await seeds.effort(segment, cid!, { elapsedTimeS: 290, startedAt: "2026-01-01T10:00:00Z" });

    const body = await leaderboard(segment, viewer!);

    expect(ranks(body)).toEqual([
      [1, bob, 280],
      [1, ann, 280],
      [3, cid, 290],
    ]);
    expect(body.entries[0]!.athlete.displayName).toBe("Bob Testeur");
    expect(body).toMatchObject({ limited: true, me: null, athleteCount: 3, nextCursor: null });
  });

  it("counts only Efforts that stand: public, outside the current privacy zone, not rejected; a suspicious one stands", async () => {
    const segment = await seeds.segment();
    const [pub, priv, zone, rejected, suspicious, viewer] = await Promise.all(
      ["Pub", "Priv", "Zone", "Rej", "Sus", "Vic"].map((name) => api.seedAthlete(name)),
    );
    await seeds.effort(segment, pub!, { elapsedTimeS: 400 });
    await seeds.effort(segment, priv!, { elapsedTimeS: 100, visibility: "private" });
    await seeds.effort(segment, priv!, { elapsedTimeS: 110, visibility: "followers" });
    await seeds.profile(zone!, { radiusM: 500 });
    await seeds.effort(segment, zone!, { elapsedTimeS: 120, toStartM: 450 });
    await seeds.effort(segment, rejected!, { elapsedTimeS: 130, status: "rejected" });
    await seeds.effort(segment, suspicious!, { elapsedTimeS: 140, status: "suspicious" });

    const body = await leaderboard(segment, viewer!);

    expect(ranks(body)).toEqual([
      [1, suspicious, 140],
      [2, pub, 400],
    ]);
    expect(body.athleteCount).toBe(2);
  });

  it("ranks after the viewer filter (Blocks both ways), but counts athletes regardless", async () => {
    const segment = await seeds.segment();
    const [fast, blocker, slow, viewer] = await Promise.all(["Fast", "Blocker", "Slow", "Vic"].map((n) => api.seedAthlete(n)));
    await seeds.effort(segment, fast!, { elapsedTimeS: 100 });
    await seeds.effort(segment, blocker!, { elapsedTimeS: 200 });
    await seeds.effort(segment, slow!, { elapsedTimeS: 300 });
    await seeds.effort(segment, viewer!, { elapsedTimeS: 400 });
    await api.sql("insert into social.athlete_block (blocker_id, blocked_id) values ($1, $2)", [viewer, fast]);
    await api.sql("insert into social.athlete_block (blocker_id, blocked_id) values ($1, $2)", [blocker, viewer]);

    const body = await leaderboard(segment, viewer!);

    expect(ranks(body)).toEqual([
      [1, slow, 300],
      [2, viewer, 400],
    ]);
    expect(body.me).toMatchObject({ rank: 2, elapsedTimeS: 400 });
    expect(body.athleteCount).toBe(4);
  });

  it("without Premium: the top 10 of Tous and the viewer's line beyond it; 403 for a sex, a filter or a cursor", async () => {
    const segment = await seeds.segment();
    const athletes = await Promise.all(Array.from({ length: 11 }, (_, i) => api.seedAthlete(`A${i}`)));
    await Promise.all(athletes.map((id, i) => seeds.effort(segment, id, { elapsedTimeS: 100 + i })));
    const viewer = athletes[10]!;

    const body = await leaderboard(segment, viewer);

    expect(body.limited).toBe(true);
    expect(body.entries.map((entry) => entry.rank)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(body.me).toMatchObject({ rank: 11, elapsedTimeS: 110 });
    expect(body.nextCursor).toBeNull();
    for (const query of ["?gender=female", "?filter=period&value=week", "?filter=following", "?cursor=abc"]) {
      const response = await api.call(`/segments/${segment}/leaderboard${query}`, viewer);
      expect(response.status, query).toBe(403);
      expect(await errorOf(response)).toBe("premium_required");
    }
  });

  it("with Premium: pages of 50 on the keyset cursor", async () => {
    const segment = await seeds.segment();
    const athletes = await Promise.all(Array.from({ length: 52 }, (_, i) => api.seedAthlete(`P${i}`)));
    await Promise.all(athletes.map((id, i) => seeds.effort(segment, id, { elapsedTimeS: 100 + Math.floor(i / 2) })));
    const viewer = athletes[0]!;
    await seeds.premium(viewer);

    const first = await leaderboard(segment, viewer);
    expect(first.limited).toBe(false);
    expect(first.entries).toHaveLength(50);
    expect(first.nextCursor).not.toBeNull();

    const second = await leaderboard(segment, viewer, `?cursor=${first.nextCursor}`);
    expect(second.entries.map((entry) => [entry.rank, entry.elapsedTimeS])).toEqual([
      [51, 125],
      [51, 125],
    ]);
    expect(second.nextCursor).toBeNull();
    const ids = [...first.entries, ...second.entries].map((entry) => entry.athlete.id);
    expect(new Set(ids).size).toBe(52);
  });

  it("filters by sex, recomputing the rank; non-binary and undisclosed athletes are only in Tous", async () => {
    const segment = await seeds.segment();
    const [man, woman, nonBinary, viewer] = await Promise.all(["Man", "Woman", "Nb", "Vic"].map((n) => api.seedAthlete(n)));
    await seeds.profile(man!, { gender: "male" });
    await seeds.profile(woman!, { gender: "female" });
    await seeds.profile(nonBinary!, { gender: "non_binary" });
    await seeds.effort(segment, nonBinary!, { elapsedTimeS: 100 });
    await seeds.effort(segment, man!, { elapsedTimeS: 200 });
    await seeds.effort(segment, woman!, { elapsedTimeS: 300 });
    await seeds.premium(viewer!);

    expect(ranks(await leaderboard(segment, viewer!, "?gender=female"))).toEqual([[1, woman, 300]]);
    expect(ranks(await leaderboard(segment, viewer!, "?gender=male"))).toEqual([[1, man, 200]]);
    expect(ranks(await leaderboard(segment, viewer!))).toHaveLength(3);
  });

  it("filters by period in the viewer's time zone, each athlete with their best Effort within it", async () => {
    const segment = await seeds.segment();
    const [ann, bob, viewer] = await Promise.all(["Ann", "Bob", "Vic"].map((n) => api.seedAthlete(n)));
    await seeds.effort(segment, ann!, { elapsedTimeS: 100, startedAt: "2020-01-01T10:00:00Z" });
    await seeds.effort(segment, ann!, { elapsedTimeS: 250, startedAt: new Date().toISOString() });
    await seeds.effort(segment, bob!, { elapsedTimeS: 200, startedAt: "2020-01-01T10:00:00Z" });
    await seeds.premium(viewer!);

    const today = await leaderboard(segment, viewer!, "?filter=period&value=today&tz=Europe/Paris");

    expect(ranks(today)).toEqual([[1, ann, 250]]);
    expect(today.me).toBeNull();
  });

  it("filters by Abonnements: accepted Follows and the viewer", async () => {
    const segment = await seeds.segment();
    const [followed, pending, stranger, viewer] = await Promise.all(["Fol", "Pen", "Str", "Vic"].map((n) => api.seedAthlete(n)));
    await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [viewer, followed]);
    await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'pending')", [viewer, pending]);
    for (const [i, id] of [followed, pending, stranger, viewer].entries()) {
      await seeds.effort(segment, id!, { elapsedTimeS: 100 + i });
    }
    await seeds.premium(viewer!);

    const body = await leaderboard(segment, viewer!, "?filter=following");

    expect(ranks(body)).toEqual([
      [1, followed, 100],
      [2, viewer, 103],
    ]);
    expect(body.me).toMatchObject({ rank: 2 });
  });

  it("filters by age and weight band from the current values; without a value, no band", async () => {
    const segment = await seeds.segment();
    const [young, adult, unknown, viewer] = await Promise.all(["Young", "Adult", "Unk", "Vic"].map((n) => api.seedAthlete(n)));
    const yearsAgo = (years: number) => `${new Date().getUTCFullYear() - years}-01-01`;
    await seeds.profile(young!, { birthDate: yearsAgo(18), weightKg: 54.5 });
    await seeds.profile(adult!, { birthDate: yearsAgo(30), weightKg: 70 });
    await seeds.effort(segment, young!, { elapsedTimeS: 100 });
    await seeds.effort(segment, adult!, { elapsedTimeS: 200 });
    await seeds.effort(segment, unknown!, { elapsedTimeS: 300 });
    await seeds.premium(viewer!);

    expect(ranks(await leaderboard(segment, viewer!, "?filter=age&value=0-19"))).toEqual([[1, young, 100]]);
    expect(ranks(await leaderboard(segment, viewer!, "?filter=age&value=25-34"))).toEqual([[1, adult, 200]]);
    expect(ranks(await leaderboard(segment, viewer!, "?filter=weight&value=0-54"))).toEqual([[1, young, 100]]);
    expect(ranks(await leaderboard(segment, viewer!, "?filter=weight&value=65-74"))).toEqual([[1, adult, 200]]);
    const invalid = await api.call(`/segments/${segment}/leaderboard?filter=age&value=18-30`, viewer!);
    expect(invalid.status).toBe(422);
    expect(await errorOf(invalid)).toBe("invalid_leaderboard_filter");
  });

  it("names the Local Legend: most Efforts over 90 days, one per Activity, the first to reach it on a tie, by sex", async () => {
    const segment = await seeds.segment();
    const [lapper, early, late, woman, viewer] = await Promise.all(
      ["Lapper", "Early", "Late", "Woman", "Vic"].map((n) => api.seedAthlete(n)),
    );
    const daysAgo = (days: number) => new Date(Date.now() - days * 86_400_000).toISOString();
    // Three laps in one Activity count once; an Effort older than 90 days does not count.
    const { activityId } = await seeds.effort(segment, lapper!, { elapsedTimeS: 100, startedAt: daysAgo(5) });
    await seeds.effort(segment, lapper!, { elapsedTimeS: 101, startedAt: daysAgo(5), activityId });
    await seeds.effort(segment, lapper!, { elapsedTimeS: 102, startedAt: daysAgo(5), activityId });
    await seeds.effort(segment, lapper!, { elapsedTimeS: 103, startedAt: daysAgo(100) });
    // Early and Late both have two; Early reached two first.
    await seeds.effort(segment, early!, { elapsedTimeS: 200, startedAt: daysAgo(30) });
    await seeds.effort(segment, early!, { elapsedTimeS: 200, startedAt: daysAgo(20) });
    await seeds.effort(segment, late!, { elapsedTimeS: 200, startedAt: daysAgo(25) });
    await seeds.effort(segment, late!, { elapsedTimeS: 200, startedAt: daysAgo(10) });
    await seeds.profile(woman!, { gender: "female" });
    await seeds.effort(segment, woman!, { elapsedTimeS: 300, startedAt: daysAgo(3) });
    await seeds.effort(segment, viewer!, { elapsedTimeS: 400, startedAt: daysAgo(2) });
    await seeds.premium(viewer!);

    const all = await leaderboard(segment, viewer!);
    expect(all.localLegend).toMatchObject({ legend: { athlete: { id: early }, effortCount: 2 }, myEffortCount: 1 });

    const women = await leaderboard(segment, viewer!, "?gender=female&filter=period&value=year");
    expect(women.localLegend.legend).toMatchObject({ athlete: { id: woman }, effortCount: 1 });
  });

  it("answers 404 segment_not_found for an unknown or deleted Segment", async () => {
    const viewer = await api.seedAthlete("Vic");
    const segment = await seeds.segment();
    await api.sql("delete from segments.segment where id = $1", [segment]);

    const response = await api.call(`/segments/${segment}/leaderboard`, viewer);

    expect(response.status).toBe(404);
    expect(await errorOf(response)).toBe("segment_not_found");
  });
});
