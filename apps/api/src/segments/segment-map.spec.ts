import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { ListMapSegmentsResponse, MapSegment } from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/** Around Annecy: a zone a screen shows at zoom ~12. */
const ANNECY = "6.10,45.88,6.16,45.92";
/** Same size, 1° further east: nothing seeded there by the other tests. */
const ELSEWHERE = "7.10,45.88,7.16,45.92";

/**
 * `GET /v1/segments` (ADR-039 §12, §15): the Segments crossing a zone of the Map tab, over real
 * HTTP, Postgres and Redis (ADR-024 §2). Segments, Activities and Efforts are seeded in SQL; the
 * viewer filter is the real one (Blocks through `PUT /v1/me/blocks/:id`).
 */
describe("GET /v1/segments (integration)", () => {
  let api: AthleteApp;
  const segmentIds: string[] = [];

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
  });

  afterAll(async () => {
    await api.sql("delete from segments.segment where id = any($1)", [segmentIds]);
    await api.close();
  });

  /** A straight Segment from `from` to `to` (`[lng, lat]`), in `zone`'s longitude band. */
  async function seedSegment(
    from: [number, number],
    to: [number, number],
    options: { name?: string; sport?: string; verified?: boolean; category?: string | null } = {},
  ): Promise<string> {
    const id = randomUUID();
    segmentIds.push(id);
    await api.sql(
      `insert into segments.segment
         (id, name, sport_type_code, path, start_point, end_point, distance_m, avg_grade, climb_category, map_polyline, verified_at)
       values ($1, $2, $3,
         ST_GeomFromEWKT($4), ST_SetSRID(ST_MakePoint($5, $6), 4326), ST_SetSRID(ST_MakePoint($7, $8), 4326),
         1234.5, 6.2, $9, '_p~iF~ps|U_ulLnnqC', $10)`,
      [
        id,
        options.name ?? "Montée du Semnoz",
        options.sport ?? "ride",
        `SRID=4326;LINESTRING Z(${from[0]} ${from[1]} 500, ${to[0]} ${to[1]} 600)`,
        from[0],
        from[1],
        to[0],
        to[1],
        options.category === undefined ? "4" : options.category,
        options.verified ? new Date() : null,
      ],
    );
    return id;
  }

  /** An Effort of a new processed Activity of `userId`, 1 km from both its ends unless said otherwise. */
  async function seedEffort(
    segmentId: string,
    userId: string,
    elapsedTimeS: number,
    options: { visibility?: string; status?: string; minDistanceToStartM?: number } = {},
  ): Promise<void> {
    const activityId = await api.seedActivity(userId, { visibility: options.visibility });
    await api.sql(
      `insert into segments.segment_effort
         (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index, end_index,
          min_distance_to_activity_start_m, min_distance_to_activity_end_m, status)
       values ($1, $2, $3, $4, now() - interval '1 hour', 0, 10, $5, 1000, $6)`,
      [activityId, segmentId, userId, elapsedTimeS, options.minDistanceToStartM ?? 1000, options.status ?? "valid"],
    );
  }

  async function search(viewer: string, query: string) {
    const response = await api.call(`/segments?${query}`, viewer);
    return { status: response.status, body: (await response.json()) as ListMapSegmentsResponse & { error?: { code: string } } };
  }

  it("lists the Segments crossing the zone, with their figures", async () => {
    const viewer = await api.seedAthlete("Lina");
    const inside = await seedSegment([6.12, 45.89], [6.13, 45.9], { name: "Col de Leschaux", verified: true });
    // Crosses the zone without starting nor ending in it.
    const crossing = await seedSegment([6.05, 45.9], [6.2, 45.9], { category: null });
    const outside = await seedSegment([6.3, 45.89], [6.31, 45.9]);

    const { status, body } = await search(viewer, `bbox=${ANNECY}`);

    expect(status).toBe(200);
    const ids = body.items.map((item) => item.id);
    expect(ids).toEqual(expect.arrayContaining([inside, crossing]));
    expect(ids).not.toContain(outside);
    expect(body.items.find((item) => item.id === inside)).toEqual<MapSegment>({
      id: inside,
      sportTypeCode: "ride",
      name: "Col de Leschaux",
      verified: true,
      starred: false,
      distanceM: 1234.5,
      averageGradePct: 6.2,
      climbCategory: "4",
      athleteCount: 0,
      myBestTimeS: null,
      leaderTimeS: null,
      mapPolyline: "_p~iF~ps|U_ulLnnqC",
    });
    expect(body.items.find((item) => item.id === crossing)?.climbCategory).toBeNull();
  });

  it("counts the athletes whose Effort stands, and shows the leader's time or the viewer's own", async () => {
    const segment = await seedSegment([7.12, 45.89], [7.13, 45.9]);
    const viewer = await api.seedAthlete("Vera");
    const [twice, fast, privately, rejected, nearHome, blocked] = await Promise.all(
      ["Paul", "Inès", "Hugo", "Rémi", "Zoé", "Bob"].map((name) => api.seedAthlete(name)),
    );
    await seedEffort(segment, twice!, 300);
    await seedEffort(segment, twice!, 280);
    await seedEffort(segment, fast!, 250);
    await seedEffort(segment, privately!, 200, { visibility: "private" });
    await seedEffort(segment, rejected!, 100, { status: "rejected" });
    // Ends 50 m from the Activity's start: inside the default 200 m privacy zone.
    await seedEffort(segment, nearHome!, 150, { minDistanceToStartM: 50 });
    await seedEffort(segment, blocked!, 240);
    expect((await api.call(`/me/blocks/${blocked}`, viewer, { method: "PUT" })).status).toBe(204);

    const seen = (await search(viewer, `bbox=${ELSEWHERE}`)).body.items.find((item) => item.id === segment);
    // The blocked athlete still counts (ADR-039 §8), but is not the viewer's leader.
    expect(seen).toMatchObject({ athleteCount: 3, myBestTimeS: null, leaderTimeS: 250 });

    // The private Effort is the athlete's own best; a rejected one is not.
    await seedEffort(segment, privately!, 90, { status: "rejected" });
    const own = (await search(privately!, `bbox=${ELSEWHERE}`)).body.items.find((item) => item.id === segment);
    expect(own).toMatchObject({ athleteCount: 3, myBestTimeS: 200, leaderTimeS: null });
  });

  it("counts an athlete without a profile with the default privacy zone, as the Leaderboard does", async () => {
    const segment = await seedSegment([7.14, 45.89], [7.15, 45.9]);
    const viewer = await api.seedAthlete("Vera");
    const [noProfile, nearHome] = await Promise.all(["Noé", "Zia"].map((name) => api.seedAthlete(name)));
    await seedEffort(segment, noProfile!, 300);
    await seedEffort(segment, nearHome!, 200, { minDistanceToStartM: 50 });
    await api.sql("delete from users.user_profile where user_id = any($1)", [[noProfile, nearHome]]);

    const seen = (await search(viewer, `bbox=${ELSEWHERE}`)).body.items.find((item) => item.id === segment);
    const board = (await (await api.call(`/segments/${segment}/leaderboard`, viewer)).json()) as { athleteCount: number };

    // Without a profile, the default 200 m zone: 50 m from home does not stand.
    expect(seen).toMatchObject({ athleteCount: 1, leaderTimeS: 300 });
    expect(board.athleteCount).toBe(1);
  });

  it("filters by sport and by the viewer's favourites, combined", async () => {
    const zone = "8.10,45.88,8.16,45.92";
    const viewer = await api.seedAthlete("Fanny");
    const other = await api.seedAthlete("Olga");
    const ride = await seedSegment([8.12, 45.89], [8.13, 45.9], { sport: "ride" });
    const starredRide = await seedSegment([8.12, 45.9], [8.13, 45.91], { sport: "ride" });
    const starredRun = await seedSegment([8.12, 45.91], [8.13, 45.915], { sport: "run" });
    await api.sql("insert into segments.segment_favorite (user_id, segment_id) values ($1, $2), ($1, $3), ($4, $2)", [
      viewer,
      starredRide,
      starredRun,
      other,
    ]);
    const ids = async (user: string, query: string) =>
      (await search(user, `bbox=${zone}${query}`)).body.items.map((item) => item.id).sort();

    expect(await ids(viewer, "")).toEqual([ride, starredRide, starredRun].sort());
    expect(await ids(viewer, "&sport=ride")).toEqual([ride, starredRide].sort());
    expect(await ids(viewer, "&favorites=true")).toEqual([starredRide, starredRun].sort());
    expect(await ids(viewer, "&sport=run&favorites=true")).toEqual([starredRun]);
    expect(await ids(other, "&favorites=true")).toEqual([starredRide]);
    const starred = (await search(viewer, `bbox=${zone}`)).body.items.filter((item) => item.starred).map((item) => item.id);
    expect(starred.sort()).toEqual([starredRide, starredRun].sort());
  });

  it("stars a card's Segment in one tap, and unstars it", async () => {
    const zone = "8.30,45.88,8.36,45.92";
    const viewer = await api.seedAthlete("Stella");
    const segment = await seedSegment([8.32, 45.89], [8.33, 45.9]);
    const starred = async () => (await search(viewer, `bbox=${zone}`)).body.items[0]?.starred;

    expect((await api.call(`/segments/${segment}/favorite`, viewer, { method: "PUT" })).status).toBe(204);
    expect((await api.call(`/segments/${segment}/favorite`, viewer, { method: "PUT" })).status).toBe(204);
    expect(await starred()).toBe(true);
    expect((await api.call(`/segments/${segment}/favorite`, viewer, { method: "DELETE" })).status).toBe(204);
    expect(await starred()).toBe(false);
    expect((await api.call(`/segments/${randomUUID()}/favorite`, viewer, { method: "PUT" })).status).toBe(404);
  });

  it("keeps the 50 Segments with the most athletes", async () => {
    const zone = "9.10,45.88,9.16,45.92";
    const viewer = await api.seedAthlete("Maël");
    const crowd = await Promise.all(["Ana", "Ben", "Cyd"].map((name) => api.seedAthlete(name)));
    const popular = await seedSegment([9.12, 45.89], [9.121, 45.891]);
    const lessPopular = await seedSegment([9.12, 45.892], [9.121, 45.893]);
    for (const athlete of crowd) await seedEffort(popular, athlete, 300);
    await seedEffort(lessPopular, crowd[0]!, 300);
    for (let i = 0; i < 50; i += 1) {
      await seedSegment([9.13, 45.89 + i * 0.0005], [9.131, 45.89 + i * 0.0005 + 0.0003]);
    }

    const { body } = await search(viewer, `bbox=${zone}`);

    expect(body.items).toHaveLength(50);
    expect(body.items.slice(0, 2).map((item) => item.id)).toEqual([popular, lessPopular]);
  });

  it("refuses a zone larger than a screen at zoom 10.5, and an invalid one", async () => {
    const viewer = await api.seedAthlete("Zack");

    // About 0.5° × 0.4° at 46° N: two screens wide at zoom 10.5.
    const tooLarge = await search(viewer, "bbox=6.0,45.7,6.5,46.1");
    expect(tooLarge.status).toBe(400);
    expect(tooLarge.body.error?.code).toBe("zone_too_large");

    for (const bbox of ["6.16,45.88,6.10,45.92", "6.1,45.88,6.16", "a,b,c,d", "6.1,45.88,6.16,95"]) {
      expect((await search(viewer, `bbox=${bbox}`)).status).toBe(422);
    }
    expect((await search(viewer, "")).status).toBe(422);
    expect((await search(viewer, `bbox=${ANNECY}&sport=swim`)).status).toBe(422);
  });
});
