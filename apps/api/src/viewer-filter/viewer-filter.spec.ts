import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import type {
  ActivityDetail,
  AthleteProfileResponse,
  AthleteSearchResponse,
  FeedResponse,
  FollowListResponse,
  FollowRequestListResponse,
  ListCommentsResponse,
  ListKudosResponse,
} from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/**
 * The viewer filter on every read path (ADR-038 §7), here with Blocks (§8): two athletes see each
 * other as nonexistent, comments and kudos they exchanged are hidden under anyone's Activity, and
 * counters do not change. Reports go through the same filter (`reports/reports.spec.ts`). Rows a
 * Block deletes (follows) are sometimes re-inserted by SQL, to prove the read path itself filters,
 * as it must for an active Ban, which deletes nothing (§6).
 */
describe("viewer filter: Blocks on every read path (integration)", () => {
  let api: AthleteApp;
  /** `viewer` blocked `blocked`; `third` is a stranger to the Block, followed by both. */
  let viewer: string;
  let blocked: string;
  let third: string;

  async function get<T>(path: string, as = viewer): Promise<T> {
    const response = await api.call(path, as);
    expect(response.status, path).toBe(200);
    return (await response.json()) as T;
  }

  async function notFound(path: string, as: string, code: string, method = "GET", body?: unknown) {
    const response = await api.call(path, as, { method, body });
    expect(response.status, `${method} ${path}`).toBe(404);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe(code);
  }

  const follow = (follower: string, followee: string) =>
    api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted') on conflict do nothing", [
      follower,
      followee,
    ]);

  const comment = async (author: string, activityId: string, body: string) =>
    (
      await api.sql<{ id: string }>(
        "insert into engagement.comment (user_id, activity_id, body) values ($1, $2, $3) returning id",
        [author, activityId, body],
      )
    )[0]!.id;

  const kudos = (giver: string, activityId: string) =>
    api.sql("insert into engagement.kudos (user_id, activity_id) values ($1, $2)", [giver, activityId]);

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
  }, 60_000);

  afterAll(async () => {
    await api?.close();
  });

  beforeEach(async () => {
    viewer = await api.seedAthlete("Vera", { lastName: "Lecteur" });
    blocked = await api.seedAthlete("Bastien", { lastName: "Zyxwbloc" });
    third = await api.seedAthlete("Tiers");
    await follow(viewer, third);
    await follow(blocked, third);
    await follow(viewer, blocked);
    expect((await api.call(`/me/blocks/${blocked}`, viewer, { method: "PUT" })).status).toBe(204);
  });

  it("feed: leaves out a hidden author's Activities and their kudos avatars, counts unchanged", async () => {
    const theirs = await api.seedActivity(blocked);
    const shared = await api.seedActivity(third);
    await kudos(blocked, shared);
    // A follow row the Block deleted: the feed must still leave the author out.
    await follow(viewer, blocked);

    const { items } = await get<FeedResponse>("/feed?limit=50");
    expect(items.map((item) => item.id)).not.toContain(theirs);
    const card = items.find((item) => item.id === shared)!;
    expect(card.recentKudos).toEqual([]);
    expect(card.engagement.kudosCount).toBe(1);
  });

  it("activity detail: 404 both ways, even public", async () => {
    const theirs = await api.seedActivity(blocked);
    const mine = await api.seedActivity(viewer);
    await notFound(`/activities/${theirs}`, viewer, "activity_not_found");
    await notFound(`/activities/${mine}`, blocked, "activity_not_found");
  });

  it("comments list: hides the hidden athlete's comments under a third party's Activity; count unchanged", async () => {
    const shared = await api.seedActivity(third);
    await comment(blocked, shared, "De Bastien");
    await comment(third, shared, "Du tiers");

    const { items } = await get<ListCommentsResponse>(`/activities/${shared}/comments`);
    expect(items.map((item) => item.body)).toEqual(["Du tiers"]);
    const { items: theirView } = await get<ListCommentsResponse>(`/activities/${shared}/comments`, blocked);
    expect(theirView.map((item) => item.body)).toEqual(["De Bastien", "Du tiers"]);
    expect((await get<ActivityDetail>(`/activities/${shared}`)).engagement.commentCount).toBe(2);
  });

  it("one comment: 404 comment_not_found for a hidden author's comment", async () => {
    const shared = await api.seedActivity(third);
    const theirs = await comment(blocked, shared, "De Bastien");
    await notFound(`/activities/${shared}/comments/${theirs}`, viewer, "comment_not_found");
  });

  it("comments on a hidden athlete's Activity: 404, to read or to add", async () => {
    const theirs = await api.seedActivity(blocked);
    await notFound(`/activities/${theirs}/comments`, viewer, "activity_not_found");
    await notFound(`/activities/${theirs}/comments`, viewer, "activity_not_found", "POST", {
      id: crypto.randomUUID(),
      body: "Coucou",
    });
  });

  it("kudos list: hides the hidden athlete's kudos; giving kudos to their Activity is 404", async () => {
    const shared = await api.seedActivity(third);
    await kudos(blocked, shared);
    await kudos(viewer, shared);

    const { items } = await get<ListKudosResponse>(`/activities/${shared}/kudos`);
    expect(items.map((item) => item.athlete.id)).toEqual([viewer]);

    const theirs = await api.seedActivity(blocked);
    await notFound(`/activities/${theirs}/kudos`, viewer, "activity_not_found", "PUT");
  });

  it("profile, its Activities, Gallery and statistics: 404 athlete_not_found both ways", async () => {
    for (const [as, of] of [[viewer, blocked], [blocked, viewer]] as const) {
      for (const path of [`/athletes/${of}`, `/athletes/${of}/activities`, `/athletes/${of}/media`, `/athletes/${of}/stats`]) {
        await notFound(path, as, "athlete_not_found");
      }
    }
  });

  it("profile header: a hidden athlete is not among « followers you know »", async () => {
    const other = await api.seedAthlete("Commun");
    await follow(blocked, other);
    await follow(viewer, blocked);

    const profile = await get<AthleteProfileResponse>(`/athletes/${other}`);
    expect(profile.followersYouKnow).toEqual([]);
    expect(profile.followerCount).toBe(1);
  });

  it("search: the hidden athlete is never found", async () => {
    const found = (q: string, as: string) =>
      get<AthleteSearchResponse>(`/athletes/search?q=${q}`, as).then(({ items }) => items.map((item) => item.athlete.id));
    expect(await found("Zyxwbloc", viewer)).not.toContain(blocked);
    expect(await found("Zyxwbloc", third)).toContain(blocked);
    expect(await found("Lecteur", blocked)).not.toContain(viewer);
  });

  it("follower and following lists: a third party's lists leave the hidden athlete out; theirs are 404", async () => {
    const followers = await get<FollowListResponse>(`/athletes/${third}/followers`);
    expect(followers.items.map((item) => item.athlete.id)).toEqual([viewer]);
    await notFound(`/athletes/${blocked}/followers`, viewer, "athlete_not_found");
    await notFound(`/athletes/${blocked}/following`, viewer, "athlete_not_found");
  });

  it("follow requests: a request from a hidden athlete is left out", async () => {
    await api.sql(
      "insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'pending')",
      [blocked, viewer],
    );
    const other = await api.seedAthlete("Demandeur");
    await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'pending')", [
      other,
      viewer,
    ]);

    const { items } = await get<FollowRequestListResponse>("/me/follow-requests");
    expect(items.map((item) => item.athlete.id)).toEqual([other]);
  });

  it("realtime: no grant for a hidden athlete's Activity", async () => {
    const theirs = await api.seedActivity(blocked);
    await notFound("/realtime/grants", viewer, "activity_not_found", "POST", { topic: `activity:${theirs}` });
  });

  it("unblocking brings back comments and kudos, but not the follows", async () => {
    const shared = await api.seedActivity(third);
    await comment(blocked, shared, "De Bastien");
    await kudos(blocked, shared);
    await api.call(`/me/blocks/${blocked}`, viewer, { method: "DELETE" });

    expect((await get<ListCommentsResponse>(`/activities/${shared}/comments`)).items).toHaveLength(1);
    expect((await get<ListKudosResponse>(`/activities/${shared}/kudos`)).items).toHaveLength(1);
    expect((await get<AthleteProfileResponse>(`/athletes/${blocked}`)).viewerFollowStatus).toBe("none");
  });
});
