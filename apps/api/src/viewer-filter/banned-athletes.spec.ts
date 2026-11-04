import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type {
  AthleteProfileResponse,
  AthleteSearchResponse,
  FeedResponse,
  FollowListResponse,
  ListCommentsResponse,
  ListKudosResponse,
} from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/**
 * An active Ban through the viewer filter (ADR-038 §6, §7): the banned athlete is hidden from
 * every viewer, nothing is deleted, counters are unchanged, and everything comes back at the end
 * date without a sign-in. The other read paths share the filter (`viewer-filter.spec.ts`).
 */
describe("viewer filter: active Bans (integration)", () => {
  let api: AthleteApp;
  let viewer: string;
  let banned: string;
  let third: string;

  async function get<T>(path: string, as = viewer): Promise<T> {
    const response = await api.call(path, as);
    expect(response.status, path).toBe(200);
    return (await response.json()) as T;
  }

  const ban = (until: string | null) =>
    api.sql(`update "user" set banned = true, ban_reason = 'Spam', ban_expires = $2 where id = $1`, [banned, until]);

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
  }, 60_000);

  afterAll(async () => {
    await api?.close();
  });

  beforeEach(async () => {
    viewer = await api.seedAthlete("Vera", { lastName: "Lectrice" });
    banned = await api.seedAthlete("Bruno", { lastName: "Qwxbanni" });
    third = await api.seedAthlete("Tiers");
    for (const [follower, followee] of [
      [viewer, banned],
      [viewer, third],
      [banned, third],
    ]) {
      await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [
        follower,
        followee,
      ]);
    }
  });

  it("hides the banned athlete everywhere, for every viewer, counters unchanged", async () => {
    const theirs = await api.seedActivity(banned);
    const shared = await api.seedActivity(third);
    await api.sql("insert into engagement.comment (user_id, activity_id, body) values ($1, $2, 'Du banni')", [banned, shared]);
    await api.sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [banned, shared]);
    await ban("2099-01-01T00:00:00Z");

    for (const as of [viewer, third]) {
      const profile = await api.call(`/athletes/${banned}`, as);
      expect(profile.status).toBe(404);
      expect(((await profile.json()) as { error: { code: string } }).error.code).toBe("athlete_not_found");
    }
    expect((await api.call(`/activities/${theirs}`, viewer)).status).toBe(404);
    const feed = await get<FeedResponse>("/feed?limit=50");
    expect(feed.items.map((item) => item.id)).not.toContain(theirs);
    expect((await get<ListCommentsResponse>(`/activities/${shared}/comments`)).items).toEqual([]);
    expect((await get<ListKudosResponse>(`/activities/${shared}/kudos`)).items).toEqual([]);
    const followers = await get<FollowListResponse>(`/athletes/${third}/followers`);
    expect(followers.items.map((item) => item.athlete.id)).toEqual([viewer]);
    const search = await get<AthleteSearchResponse>("/athletes/search?q=Qwxbanni");
    expect(search.items).toEqual([]);

    // Counters unchanged: the banned athlete's follow still counts.
    expect((await get<AthleteProfileResponse>(`/athletes/${third}`)).followerCount).toBe(2);
  });

  it("everything comes back once the end date has passed, without a sign-in", async () => {
    await ban("2000-01-01T00:00:00Z");
    expect((await api.call(`/athletes/${banned}`, viewer)).status).toBe(200);
  });

  it("a permanent Ban hides until it is lifted", async () => {
    await ban(null);
    expect((await api.call(`/athletes/${banned}`, viewer)).status).toBe(404);
    await api.sql(`update "user" set banned = false, ban_reason = null where id = $1`, [banned]);
    expect((await api.call(`/athletes/${banned}`, viewer)).status).toBe(200);
  });
});
