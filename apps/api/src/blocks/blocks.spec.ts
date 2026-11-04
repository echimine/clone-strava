import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { BlockedAthleteListResponse, FollowResponse } from "@repo/contracts";
import { bootstrapAthleteApp, type AthleteApp } from "../testing/athlete-app.js";

/**
 * Block an athlete (ADR-038 §8): `PUT`, `DELETE` and `GET /v1/me/blocks` over the real `AppModule`.
 * What a Block hides on each read path is in `viewer-filter/viewer-filter.spec.ts`.
 */
describe("blocks (integration)", () => {
  let api: AthleteApp;

  const block = (viewer: string, athleteId: string) => api.call(`/me/blocks/${athleteId}`, viewer, { method: "PUT" });
  const unblock = (viewer: string, athleteId: string) =>
    api.call(`/me/blocks/${athleteId}`, viewer, { method: "DELETE" });
  const follow = (viewer: string, athleteId: string) => api.call(`/athletes/${athleteId}/follow`, viewer, { method: "PUT" });

  async function blocks(viewer: string) {
    const response = await api.call("/me/blocks", viewer);
    expect(response.status).toBe(200);
    return (await response.json()) as BlockedAthleteListResponse;
  }

  async function errorCode(response: Response) {
    return ((await response.json()) as { error: { code: string } }).error.code;
  }

  beforeAll(async () => {
    api = await bootstrapAthleteApp();
  }, 60_000);

  afterAll(async () => {
    await api?.close();
  });

  it("blocks idempotently and lists the athlete with their identity", async () => {
    const viewer = await api.seedAthlete("Vera");
    const target = await api.seedAthlete("Tom", { lastName: "Bloqué" });

    expect((await block(viewer, target)).status).toBe(204);
    expect((await block(viewer, target)).status).toBe(204);

    const { items } = await blocks(viewer);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ athlete: { id: target, displayName: "Tom Bloqué", avatarUrl: null } });
    expect(Date.parse(items[0]!.blockedAt)).not.toBeNaN();
  });

  it("shows each athlete only those they blocked, most recent first", async () => {
    const viewer = await api.seedAthlete("Vera");
    const first = await api.seedAthlete("Premier");
    const second = await api.seedAthlete("Second");
    await block(viewer, first);
    await block(viewer, second);

    expect((await blocks(viewer)).items.map((item) => item.athlete.id)).toEqual([second, first]);
    expect((await blocks(first)).items).toEqual([]);
  });

  it("deletes follows and follow requests in both directions, and refuses a new follow while blocked", async () => {
    const viewer = await api.seedAthlete("Vera");
    const target = await api.seedAthlete("Tom");
    await api.sql("insert into social.follow_settings (user_id, approve_followers) values ($1, true)", [viewer]);
    await api.sql(
      "insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted'), ($2, $1, 'pending')",
      [viewer, target],
    );

    await block(viewer, target);

    const rows = await api.sql(
      "select 1 from social.follow where (follower_id, followee_id) in (($1::uuid, $2::uuid), ($2::uuid, $1::uuid))",
      [viewer, target],
    );
    expect(rows).toHaveLength(0);
    for (const [follower, followee] of [[viewer, target], [target, viewer]] as const) {
      const response = await follow(follower, followee);
      expect(response.status).toBe(404);
      expect(await errorCode(response)).toBe("athlete_not_found");
    }
  });

  it("unblocks idempotently; follows are not restored, and following is possible again", async () => {
    const viewer = await api.seedAthlete("Vera");
    const target = await api.seedAthlete("Tom");
    await api.sql("insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')", [
      viewer,
      target,
    ]);
    await block(viewer, target);

    expect((await unblock(viewer, target)).status).toBe(204);
    expect((await unblock(viewer, target)).status).toBe(204);
    expect((await blocks(viewer)).items).toEqual([]);
    expect(await api.sql("select 1 from social.follow where follower_id = $1", [viewer])).toHaveLength(0);

    const response = await follow(viewer, target);
    expect(response.status).toBe(200);
    expect(((await response.json()) as FollowResponse).viewerFollowStatus).toBe("accepted");
  });

  it("refuses to block oneself (422) or an unknown athlete (404)", async () => {
    const viewer = await api.seedAthlete("Vera");

    const self = await block(viewer, viewer);
    expect(self.status).toBe(422);
    expect(await errorCode(self)).toBe("cannot_block_self");

    const unknown = await block(viewer, crypto.randomUUID());
    expect(unknown.status).toBe(404);
    expect(await errorCode(unknown)).toBe("athlete_not_found");
  });
});
